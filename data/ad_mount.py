#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# Helpers for Active Directory mount

from __future__ import annotations
from pathlib import Path
import ipaddress
import logging
from os import environ as env

import re
import socket
import subprocess
from ldap3 import Server, Connection, SASL, GSSAPI, ALL
from sectools.windows.ldap.ldap import ldap3_kerberos_login
from getpass import getuser
import os
import pwd as _pwd

# Add pyDescribeNTSecurityDescriptor tp the PATH
SETUP_ROOT = Path(__file__).parent.parent
NTSEC_DIR = "external/pyDescribeNTSecurityDescriptor"
NTSEC_FILE = "DescribeNTSecurityDescriptor.py"
if (Path(SETUP_ROOT) / NTSEC_DIR / NTSEC_FILE).is_file():
    import sys
    sys.path.insert(0, str(Path(SETUP_ROOT) / NTSEC_DIR))

import DescribeNTSecurityDescriptor as ntsec

SYSVOL_CACHE = "/var/cache/sysvol"
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

def mount_main():
    dc = DC()
    dc.connect()
    logger.info("Successfully connected to LDAP server")

    cache = SysvolCache(dc.domain)
    cache.process_mounts(dc.ldap)
    logger.info("Successfully applied GPOs from Sysvol cache")

class User:
    def __init__(self, username: str = "", uid: int = 0, sid: str = ""):
        self.username = username
        self.uid = uid
        self.sid = sid
        self.sid_set: set[str] = set()
        self.sid_set.add(self.sid) # Could match the user SID itself and not just a group.

class DriveDescriptor:
    pass

class MyLdap(ntsec.LDAPSearcher):

    def get_gpo_security(self, gpo_cn: str) -> tuple[str, ntsec.NTSecurityDescriptor]:
        """
        Returns the display name and security descriptor for a given GPO CN.
        """
        gpo_dn = f"CN={gpo_cn},CN=Policies,CN=System,{self.search_base}"
        attributes = ['displayName', 'nTSecurityDescriptor']
        res = self.query(gpo_dn, "(objectClass=*)", attributes=attributes)
        if gpo_dn.lower() not in res.keys():
            raise ValueError(f"GPO with CN '{gpo_cn}' not found in LDAP")
        entry = res[gpo_dn.lower()]

        logger.debug(f"Identified GPO '{entry[attributes[0]]}'")
        return entry[attributes[0]], ntsec.NTSecurityDescriptor(entry[attributes[1]], ldap_searcher=self)

    def retrieve_user_info(self, user_id: int) -> User:
        """
        Retrieves the username, SID and all group memberships for a given Linux UID.

        Uses the AD 'tokenGroups' operational attribute: the DC computes the complete
        flat list of group SIDs (including all nested/universal groups) in a single
        query — exactly as Windows does when building an access token.
        """

        # Can throw a KeyError, which we do want to propagate up
        username: str = _pwd.getpwuid(user_id).pw_name

        # Single LDAP query: objectSid + tokenGroups (DC expands all nested groups)
        attrs = ["sAMAccountName", "objectSid", "tokenGroups"]
        res = self.query(self.search_base, f"(sAMAccountName={username})", attributes=attrs)
        if len(res.keys()) != 1:
            raise ValueError(f"User with sAMAccountName '{username}' not found in LDAP")
        entry_dn, entry = next(iter(res.items()))

        username = entry[attrs[0]]
        sid: str = entry[attrs[1]]
        token_groups: list[str] = entry[attrs[2]] if attrs[2] in entry else []
        logger.info(f"User '{username}' found in LDAP")
        user = User(username=username, uid=user_id, sid=sid)

        # Build the flat SID set
        for group_sid in token_groups:
            user.sid_set.add(ntsec.SID.fromRawBytes(group_sid).toString())

        # Add well-known implicit SIDs that Windows always includes in the access token
        # for any authenticated domain user. These are never returned by tokenGroups
        # because they are not AD objects — they are synthetic SIDs added at logon time.
        user.sid_set.add("S-1-1-0")   # Everyone
        user.sid_set.add("S-1-5-11")  # Authenticated Users
        user.sid_set.add("S-1-5-15")  # This Organization

        logger.debug(f"Retrieved user: {user.username}")

        return user

    @property
    def search_base(self) -> str:
        return self.ldap_server.info.other["defaultNamingContext"][0]

    def __init__(self, ldap_server: Server, ldap_session: Connection):
        super().__init__(ldap_server=ldap_server, ldap_session=ldap_session)


class SysvolCache:

    def __init__(self, domain: str):
        self.cache_path = Path(f"{SYSVOL_CACHE}/{domain}")
        if not self.cache_path.is_dir():
            raise ValueError(f"Sysvol cache directory does not exist: {self.cache_path}")

        # Cache some values
        self.cur_user: User = None

        # Precompile regex to extract GPO ID from XML file paths
        e_path = re.escape(str(self.cache_path))
        self._gpo_regex = re.compile(rf"^{e_path}/Policies/(\{{[0-9a-fA-F-]+\}})/.*$")

    def process_mounts(self, ldap: ntsec.LDAPSearcher) -> list[DriveDescriptor]:
        # Iterate over all Drive and Folder XML files in the cache
        for xml_file in self.cache_path.glob("**/Drives.xml"):
            logger.debug(f"Processing sysvol XML file: {xml_file}")
            if self._is_gpo_applied(self._extract_gpo_id(xml_file), ldap):
                self._process_drive_xml(xml_file)
        for xml_file in self.cache_path.glob("**/Folders.xml"):
            logger.debug(f"Processing sysvol XML file: {xml_file}")
            if self._is_gpo_applied(self._extract_gpo_id(xml_file), ldap):
                self._process_folder_xml(xml_file)

    def _extract_gpo_id(self, xml_file: Path) -> str:
        return self._gpo_regex.match(str(xml_file)).group(1)

    def _is_gpo_applied(self, gpo_cn: str, ldap: MyLdap) -> bool:
        # Query the GPO
        display_name, sec = ldap.get_gpo_security(gpo_cn)

        # Retrieve the different ACEs saying this GPO applies to me
        applicables = []
        for ace in sec.dacl:
            if self._is_security_filter(ace):
                if self._is_this_me(ldap, ace.ace_sid):
                    logger.info(f"GPO '{display_name}' applies to '{self.cur_user.username}' via ACE '{ace.ace_sid.displayName}'")
                    applicables.append(ace)
                else:
                    logger.debug(f"GPO '{display_name}' has a security filter ACE for '{ace.ace_sid.displayName}' but it doesn't apply to '{self.cur_user.username}'")

        if len(applicables) < 1:
            logger.info(f"GPO '{display_name}' doesn't concern '{self.cur_user.username}'")
            return False

        # Alright, this GPO applies to me. Make sure we were actually allowed to read this
        can_read = False
        for ace in sec.dacl:
            if self._has_read(ace) and self._is_this_me(ldap, ace.ace_sid):
                if self._is_deny(ace):
                    can_read = False
                    break
                elif self._is_allow(ace):
                    can_read = True
                else:
                    logger.debug(f"GPO '{display_name}' doesn't specify allow/deny")

        if not can_read:
            logger.info(f"GPO '{display_name}' is not readable by '{self.cur_user.username}' according to its ACL")
            return False

        # First, check if we are explicitely denied by this policy
        for ace in applicables:
            if self._is_deny(ace):
                logger.info(f"GPO '{display_name}' explicitly denies access via '{ace.ace_sid.displayName}'")
                return False

        # Then check if we are explicitely allowed by this policy
        for ace in applicables:
            if self._is_allow(ace):
                logger.info(f"GPO '{display_name}' explicitly allows access via '{ace.ace_sid.displayName}'")
                return True

        # Unexpected situation
        logger.warning(f"GPO '{display_name}' applies to me but doesn't explicitly allow or deny access")
        return False

    def _has_read(self, ace) -> bool:
        value = ace.mask["AccessMask"]
        mask = (
                ntsec.AccessMaskFlags.GENERIC_READ |
                ntsec.AccessMaskFlags.GENERIC_ALL |
                ntsec.AccessMaskFlags.DS_READ_PROPERTY |
                ntsec.AccessMaskFlags.READ_CONTROL
            )
        return bool(value & mask)

    def _is_security_filter(self, ace) -> bool:
        is_filter = bool(ace.mask["AccessMask"] & ntsec.AccessMaskFlags.DS_CONTROL_ACCESS)
        if not is_filter or not self._is_object(ace):
            return False
        # If it's a control access ACE, it must have the correct GUID to be a security filter
        if hasattr(ace, "object_type") and ace.object_type is not None:
            guid = getattr(ace.object_type, "ObjectTypeGuid", None)
            if guid and guid.toFormatD() == ntsec.ExtendedRights.APPLY_GROUP_POLICY.value:
                return True
            else:
                logger.warning(f"ACE has control access but wrong GUID: {guid}")
        else:
            logger.error(f"ACE has control access but can't validate it: {hasattr(ace, 'object_type')}")
        return False

    def _is_deny(self, ace) -> bool:
        return ace.header.AceType in (
            ntsec.AccessControlEntry_Type.ACCESS_DENIED_ACE_TYPE,
            ntsec.AccessControlEntry_Type.ACCESS_DENIED_OBJECT_ACE_TYPE,
        )

    def _is_allow(self, ace) -> bool:
        return ace.header.AceType in (
            ntsec.AccessControlEntry_Type.ACCESS_ALLOWED_ACE_TYPE,
            ntsec.AccessControlEntry_Type.ACCESS_ALLOWED_OBJECT_ACE_TYPE,
        )

    def _is_object(self, ace) -> bool:
        return ace.header.AceType in (
            ntsec.AccessControlEntry_Type.ACCESS_DENIED_OBJECT_ACE_TYPE,
            ntsec.AccessControlEntry_Type.ACCESS_ALLOWED_OBJECT_ACE_TYPE,
        )

    def _is_this_me(self, ldap: MyLdap, ace_sid: ntsec.ACESID) -> bool:
        """
        Returns True if the ACE SID matches the current user or any of their (nested) group SIDs.
        User identity is anchored to os.getuid() (kernel UID) resolved via SSSD InfoPipe.
        Group memberships are resolved via LDAP.
        """
        if self.cur_user is None:
            self.cur_user = ldap.retrieve_user_info(os.getuid())

        ace_sid_str = ace_sid.sid.toString()
        return ace_sid_str in self.cur_user.sid_set

    def _process_drive_xml(self, xml_file: Path) -> None:
        pass

    def _process_folder_xml(self, xml_file: Path) -> None:
        pass

class DC:
    def __init__(self):
        self.domain = self.__get_domain()
        self.dc = self.__get_closest_dc()
        self.ldap: MyLdap = None

    def is_valid_fqdn(self, fqdn: str) -> bool:
        # RFC 1035: labels 1-63 chars, total <= 253, only a-z0-9- (no _), no leading/trailing hyphen
        fqdn_regex = re.compile(
            r'^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*\.?$'
        )
        return bool(fqdn_regex.match(fqdn))

    def is_valid_ip(self, ip: str) -> bool:
        try:
            ipaddress.IPv4Address(ip)
            return True
        except ipaddress.AddressValueError:
            return False

    def __get_domain(self) -> str:
        domain = subprocess.run(["realm", "list", "--name-only"], check=True, capture_output=True, text=True).stdout.strip()
        if not self.is_valid_fqdn(domain):
            raise ValueError(f"Invalid domain name: {domain}")
        logger.debug(f"Retrieved domain: {domain}")
        return domain

    def __get_closest_dc(self) -> str:
        # Retrieve the list of DCs for the domain using DNS SRV records
        query = ["host", "-t", "SRV", f"_ldap._tcp.{self.domain}"]
        result = subprocess.run(query, check=True, capture_output=True, text=True).stdout.splitlines()
        dc_list = []
        for line in result:
            if "SRV" in line:
                parts = line.split()
                if len(parts) >= 4:
                    dc = parts[-1].rstrip('.').strip()
                    if self.is_valid_fqdn(dc):
                        logger.debug(f"Found DC: {dc}")
                        dc_list.append(dc)
                    else:
                        logger.warning(f"Invalid DC FQDN found in SRV record: {dc}")
        if len(dc_list) < 1:
            raise ValueError(f"No valid DCs found for domain {self.domain}")

        # Retrieve the local default interface
        query = ["ip", "route", "get", "1"]
        result = subprocess.run(query, check=True, capture_output=True, text=True).stdout.strip()
        local_interface = None
        parts = result.split()
        for i in range(len(parts)):
            if parts[i] == "dev" and i + 1 < len(parts):
                local_interface = parts[i + 1].strip()
                logger.debug(f"Local default route interface: {local_interface}")
                break
        if local_interface is None or len(local_interface) < 1:
            raise ValueError("Could not determine local default route interface")

        # Retrieve IP and netmask for that interface
        query = ["ip", "-o", "-f", "inet", "addr", "show", "dev", local_interface]
        result = subprocess.run(query, check=True, capture_output=True, text=True).stdout.strip()
        ip_address = None
        netmask = None
        parts = result.split()
        for i in range(len(parts)):
            if parts[i] == "inet" and i + 1 < len(parts):
                ip_address, netmask = parts[i + 1].split("/")
                logger.debug(f"Local IP address: {ip_address}, Netmask: {netmask}")
                break
        if ip_address is None or not self.is_valid_ip(ip_address):
            raise ValueError("Could not determine local IP address and netmask")
        if netmask is None or not netmask.isdigit() or int(netmask) < 1 or int(netmask) > 32:
            raise ValueError("Could not determine local netmask")

        # Select a favored DC
        favored_dc = None
        for dc in dc_list:
            # Get IP address of the DC
            dc_ip = socket.gethostbyname(dc)
            if not self.is_valid_ip(dc_ip):
                logger.warning(f"Could not resolve IP for DC {dc}")
                continue

            # Is this DC reachable? Test with ping
            ping_result = subprocess.run(["ping", "-c", "1", dc_ip], check=False)
            if ping_result.returncode == 0:
                if favored_dc is None:
                    favored_dc = dc
                    logger.debug(f"Selected DC {favored_dc} for being reachable")
            else:
                logger.warning(f"DC {dc} is not reachable via ping")
                continue

            # Is this DC in the same subnet as we are?
            dc_net = ipaddress.ip_network(f"{dc_ip}/{netmask}", strict=False)
            local_net = ipaddress.ip_network(f"{ip_address}/{netmask}", strict=False)
            if local_net.overlaps(dc_net):
                favored_dc = dc
                logger.debug(f"Selected DC {favored_dc} for being in the same subnet")
                break
            else:
                logger.debug(f"DC {dc} is not in the same subnet")

        if favored_dc is None:
            raise ValueError(f"No reachable DCs found for domain {self.domain}")
        return favored_dc

    def connect(self):
        server = Server(f'ldap://{self.dc}', get_info=ALL)
        conn = Connection(server, authentication=SASL, sasl_mechanism=GSSAPI)
        conn.bind()

        self.ldap = MyLdap(ldap_server=server, ldap_session=conn)

if __name__ == "__main__":
    logger.info(f"Starting AD Drive Mount for: {env.get('USER')}")
    mount_main()
    logger.info(f"Finished AD Drive Mount")
