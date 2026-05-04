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
import time
from typing import Optional
from ldap3 import Server, Connection, SASL, GSSAPI, ALL
import urllib.parse
import os
import pwd as _pwd
import xml.etree.ElementTree as ET
import smbclient
import sys
from gssapi.exceptions import GSSError
from smbprotocol.exceptions import NtStatus, SMBOSError
from gi.repository import Gio, GLib

# Add pyDescribeNTSecurityDescriptor tp the PATH
SETUP_ROOT = Path(__file__).parent.parent
NTSEC_DIR = "external/pyDescribeNTSecurityDescriptor"
NTSEC_FILE = "DescribeNTSecurityDescriptor.py"
if (Path(SETUP_ROOT) / NTSEC_DIR / NTSEC_FILE).is_file():
    sys.path.insert(0, str(Path(SETUP_ROOT) / NTSEC_DIR))
    import DescribeNTSecurityDescriptor as ntsec
elif (Path(__file__).parent / "lib" / NTSEC_FILE).is_file():
    sys.path.insert(0, str(Path(__file__).parent / "lib"))
    import DescribeNTSecurityDescriptor as ntsec

# Configuration variables
SYSVOL_CACHE = "/var/cache/sysvol"
BOOKMARK_LABEL = "Drives"
BOOKMARK_LOCATION = Path.home() / BOOKMARK_LABEL

# Logger
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)


def mount_main() -> None:
    """
    Main function to be called for mounting drives based on AD GPOs.
    """

    dc = DC()
    dc.connect()
    logger.info("Successfully connected to LDAP server")

    cache = SysvolCache(dc.domain)
    cache.process_mounts(dc.ldap)
    logger.info("Successfully applied GPOs from Sysvol cache")


class User:
    """Represents a user."""

    def __init__(self, username: str = "", uid: int = 0, sid: str = ""):
        """Initializes a User object with the given username, UID and SID."""

        self.username = username
        self.uid = uid
        self.sid = sid
        self.sid_set: set[str] = set()
        self.sid_set.add(
            self.sid
        )  # Could match the user SID itself and not just a group.

        self._cur_kerberos_cache: Optional[str] = None

    @property
    def kerberos_cache(self) -> str:
        """Returns the Kerberos cache name for this user, which is needed for GSSAPI authentication."""

        if self._cur_kerberos_cache:
            return self._cur_kerberos_cache

        latest_mtime = 0.0
        latest_ccfile = None
        for _ccfile in Path("/tmp").glob(f"krb5cc_{self.uid}_*"):
            if not _ccfile.is_file():
                continue
            try:
                mtime = _ccfile.stat().st_mtime
            except BaseException as e:
                logger.warning(
                    f"Could not stat Kerberos cache file '{_ccfile}': {str(e)}"
                )
                continue
            if latest_mtime < mtime or latest_mtime == 0.0:
                try:
                    cmd = ["klist", "-s", "-c", f"FILE:{_ccfile}"]
                    subprocess.run(cmd, check=True)
                except subprocess.CalledProcessError as e:
                    if e.returncode == 1:
                        logger.warning(f"Kerberos cache file '{_ccfile}' is expired")
                    raise e
                latest_mtime = mtime
                latest_ccfile = _ccfile

        if latest_ccfile is None:
            raise ValueError(f"No valid Kerberos cache file found for UID {self.uid}")

        self._cur_kerberos_cache = f"FILE:{latest_ccfile}"
        return self._cur_kerberos_cache


class MyLdap(ntsec.LDAPSearcher):  # type: ignore[misc]
    """Custom LDAP searcher with helper functions."""

    def get_gpo_security(self, gpo_cn: str) -> tuple[str, ntsec.NTSecurityDescriptor]:
        """Returns the display name and security descriptor for a given GPO CN."""

        gpo_dn = f"CN={gpo_cn},CN=Policies,CN=System,{self.search_base}"
        attributes = ["displayName", "nTSecurityDescriptor"]
        res = self.query(gpo_dn, "(objectClass=*)", attributes=attributes)
        if gpo_dn.lower() not in res.keys():
            raise ValueError(f"GPO with CN '{gpo_cn}' not found in LDAP")
        entry = res[gpo_dn.lower()]

        logger.debug(f"Identified GPO '{entry[attributes[0]]}'")
        return entry[attributes[0]], ntsec.NTSecurityDescriptor(
            entry[attributes[1]], ldap_searcher=self
        )

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
        res = self.query(
            self.search_base, f"(sAMAccountName={username})", attributes=attrs
        )
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
        user.sid_set.add("S-1-1-0")  # Everyone
        user.sid_set.add("S-1-5-11")  # Authenticated Users
        user.sid_set.add("S-1-5-15")  # This Organization

        logger.debug(f"Retrieved user: {user.username}")

        return user

    @property
    def search_base(self) -> str:
        """Returns the default naming context from the LDAP server info."""
        return str(self.ldap_server.info.other["defaultNamingContext"][0])

    def __init__(self, ldap_server: Server, ldap_session: Connection):
        """Initializes the MyLdap object with the given LDAP server and session."""
        super().__init__(ldap_server=ldap_server, ldap_session=ldap_session)


class SysvolCache:
    """Represents the local cached Sysvol directory."""

    def __init__(self, domain: str):
        """Initializes the SysvolCache for the given domain and validates the cache directory."""

        self.cache_path = Path(f"{SYSVOL_CACHE}/{domain}")
        if not self.cache_path.is_dir():
            raise ValueError(
                f"Sysvol cache directory does not exist: {self.cache_path}"
            )

        # Cache some values
        self._cur_user: Optional[User] = None

        # Precompile regex to extract GPO ID from XML file paths
        e_path = re.escape(str(self.cache_path))
        self._gpo_regex = re.compile(rf"^{e_path}/Policies/(\{{[0-9a-fA-F-]+\}})/.*$")

    @property
    def cur_user(self) -> User:
        """Returns the current user information, or None if not yet retrieved."""
        if self._cur_user is None:
            raise ValueError("Current user information has not been retrieved yet")

        return self._cur_user

    def process_mounts(self, ldap: ntsec.LDAPSearcher) -> None:
        """Process Folders.xml and Drives.xml files"""

        for xml_file in self.cache_path.glob("**/Folders.xml"):
            logger.debug(f"Processing sysvol XML file: {xml_file}")
            if self._is_gpo_applied(self._extract_gpo_id(xml_file), ldap):
                self._process_folder_xml(xml_file)
        for xml_file in self.cache_path.glob("**/Drives.xml"):
            logger.debug(f"Processing sysvol XML file: {xml_file}")
            if self._is_gpo_applied(self._extract_gpo_id(xml_file), ldap):
                self._process_drive_xml(xml_file)

        # Fix bookmark
        self._ensure_nemo_bookmark()

    def _extract_gpo_id(self, xml_file: Path) -> str:
        """Extracts the GPO ID (GUID) from the given XML file."""
        match = self._gpo_regex.match(str(xml_file))
        if not match:
            raise ValueError(f"Invalid GPO XML file path: {xml_file}")
        return match.group(1)

    def _is_gpo_applied(self, gpo_cn: str, ldap: MyLdap) -> bool:
        """Determines if the given GPO applies to the current user."""

        # Query the GPO
        display_name, sec = ldap.get_gpo_security(gpo_cn)

        # Retrieve the different ACEs saying this GPO applies to me
        applicables = []
        for ace in sec.dacl:
            if self._is_security_filter(ace):
                if self._is_this_me(ldap, ace.ace_sid):
                    logger.info(
                        f"GPO '{display_name}' applies to '{self.cur_user.username}' via ACE '{ace.ace_sid.displayName}'"
                    )
                    applicables.append(ace)
                else:
                    logger.debug(
                        f"GPO '{display_name}' has a security filter ACE for '{ace.ace_sid.displayName}' but it doesn't apply to '{self.cur_user.username}'"
                    )

        if len(applicables) < 1:
            logger.info(
                f"GPO '{display_name}' doesn't concern '{self.cur_user.username}'"
            )
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
            logger.info(
                f"GPO '{display_name}' is not readable by '{self.cur_user.username}' according to its ACL"
            )
            return False

        # First, check if we are explicitely denied by this policy
        for ace in applicables:
            if self._is_deny(ace):
                logger.info(
                    f"GPO '{display_name}' explicitly denies access via '{ace.ace_sid.displayName}'"
                )
                return False

        # Then check if we are explicitely allowed by this policy
        for ace in applicables:
            if self._is_allow(ace):
                logger.info(
                    f"GPO '{display_name}' explicitly allows access via '{ace.ace_sid.displayName}'"
                )
                return True

        # Unexpected situation
        logger.warning(
            f"GPO '{display_name}' applies to me but doesn't explicitly allow or deny access"
        )
        return False

    def _has_read(self, ace: ntsec.AccessControlEntry) -> bool:
        """Checks if the given ACE defines read permissions."""

        value = ace.mask["AccessMask"]
        mask = (
            ntsec.AccessMaskFlags.GENERIC_READ
            | ntsec.AccessMaskFlags.GENERIC_ALL
            | ntsec.AccessMaskFlags.DS_READ_PROPERTY
            | ntsec.AccessMaskFlags.READ_CONTROL
        )
        return bool(value & mask)

    def _is_security_filter(self, ace: ntsec.AccessControlEntry) -> bool:
        """Checks if the given ACE is a security filter ACE for Group Policy."""

        is_filter = bool(
            ace.mask["AccessMask"] & ntsec.AccessMaskFlags.DS_CONTROL_ACCESS
        )
        if not is_filter or not self._is_object(ace):
            return False
        # If it's a control access ACE, it must have the correct GUID to be a security filter
        if hasattr(ace, "object_type") and ace.object_type is not None:
            guid = getattr(ace.object_type, "ObjectTypeGuid", None)
            if (
                guid
                and guid.toFormatD() == ntsec.ExtendedRights.APPLY_GROUP_POLICY.value
            ):
                return True
            else:
                logger.warning(f"ACE has control access but wrong GUID: {guid}")
        else:
            logger.error(
                f"ACE has control access but can't validate it: {hasattr(ace, 'object_type')}"
            )
        return False

    def _is_deny(self, ace: ntsec.AccessControlEntry) -> bool:
        """Checks if the given ACE is a deny ACE."""

        return ace.header.AceType in (
            ntsec.AccessControlEntry_Type.ACCESS_DENIED_ACE_TYPE,
            ntsec.AccessControlEntry_Type.ACCESS_DENIED_OBJECT_ACE_TYPE,
        )

    def _is_allow(self, ace: ntsec.AccessControlEntry) -> bool:
        """Checks if the given ACE is an allow ACE."""

        return ace.header.AceType in (
            ntsec.AccessControlEntry_Type.ACCESS_ALLOWED_ACE_TYPE,
            ntsec.AccessControlEntry_Type.ACCESS_ALLOWED_OBJECT_ACE_TYPE,
        )

    def _is_object(self, ace: ntsec.AccessControlEntry) -> bool:
        """Checks if the given ACE is an object ACE (not a simple ACE)."""

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
        if self._cur_user is None:
            self._cur_user = ldap.retrieve_user_info(os.getuid())

        ace_sid_str = ace_sid.sid.toString()
        return ace_sid_str in self.cur_user.sid_set

    def _process_drive_xml(self, xml_file: Path) -> None:
        """Processes a Drives.xml file and applies the specified drive actions."""

        tree = ET.parse(xml_file)
        root = tree.getroot()
        for drive in root.findall("Drive"):
            name = drive.get("name")
            if name is None:
                raise ValueError(f"Drive element missing 'name' attribute in '{xml_file}'")
            name = self._expand_var(name)
            if drive.get("userContext") != "1":
                logger.warning(
                    f"Only supporting Drive actions ran within the user context. Skipping '{name}'"
                )
                continue
            props = drive.find("Properties")
            if props is None:
                raise ValueError(f"Drive element missing 'Properties' element in '{xml_file}'")
            if props.get("allDrives") != "NOCHANGE":
                logger.warning(
                    f"Unsupported Drive property allDrives='{props.get('allDrives')}' for '{name}'. Skipping."
                )
                continue
            is_shown = props.get("thisDrive") == "SHOW"
            if not is_shown:
                logger.warning(
                    f"Unsupported Drive property thisDrive='{props.get('thisDrive')}' for '{name}'. Skipping."
                )
                continue
            use_letter = props.get("useLetter") == "1"
            action = props.get("action")
            path = props.get("path")
            if not path:
                raise ValueError(f"Drive element missing 'path' property in '{xml_file}' for '{name}'")
            path = self._expand_var(path)
            label = props.get("label")
            if not label:
                raise ValueError(f"Drive element missing 'label' property in '{xml_file}' for '{name}'")
            label = self._expand_var(label)
            letter = props.get("letter")
            if not letter:
                raise ValueError(f"Drive element missing 'letter' property in '{xml_file}' for '{name}'")
            is_persistent = props.get("persistent") == "1"

            if use_letter and len(letter) > 0:
                label = label + f" ({letter})"

            if action in ("C", "U"):
                logger.info(
                    f"Mounting '{name}' as '{label}' to '{path}' (persistent={is_persistent})"
                )
                self._mount(path, label, is_persistent)
            elif action == "D":
                logger.warning(f"Removing '{name}' as '{label}'")
                self._unmount(path, label)
            elif action == "R":
                logger.warning(
                    f"Replacing '{name}' as '{label}' to '{path}' (persistent={is_persistent})"
                )
                self._unmount(path, label)
                self._mount(path, label, is_persistent)
            else:
                logger.warning(
                    f"Unsupported Drive action='{action}' for '{name}'. Skipping."
                )
                continue

            logger.info(f"Successfully processed Drive action='{action}' for '{name}'")

    def _unc_to_smb(self, unc_path: str) -> str:
        """Converts a UNC path to an SMB URI compatible with smbclient and gvfs."""

        # Convert a UNC path like \\server\share\path to a smbclient-compatible path like //server/share/path
        if not unc_path.startswith("\\\\"):
            raise ValueError(f"Invalid UNC path: {unc_path}")
        parts = unc_path[2:].split("\\")
        if len(parts) < 2:
            raise ValueError(f"Invalid UNC path: {unc_path}")
        server = parts[0]
        share = parts[1]
        subpath = "/".join(parts[2:]) if len(parts) > 2 else ""
        smb_path = f"smb://{server}/{share}"
        if subpath:
            smb_path += f"/{subpath}"
        return smb_path

    def _ensure_nemo_bookmark(self) -> None:
        """Ensures that the mounted Drives folder is bookmarked in the user's file manager (Nemo)."""

        bookmarks_file = Path.home() / ".config" / "gtk-3.0" / "bookmarks"
        uri = f"file://{BOOKMARK_LOCATION.as_posix()}"
        entry = f"{uri} {BOOKMARK_LABEL}"

        lines = []
        if os.path.exists(bookmarks_file):
            with open(bookmarks_file, encoding="utf-8") as f:
                lines = [
                    cur_line.strip() for cur_line in f.readlines() if cur_line.strip()
                ]

        # Check if already present
        for line in lines:
            if line.startswith(uri):
                return

        # Append (do not reorder)
        lines.append(entry)

        # Write back
        with open(bookmarks_file, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

    def _split_smb(self, uri: str) -> dict[str, str]:
        """
        Splits an SMB URI into its components: server, share and subpath.
        This assumes that the first part of the path is always the share
        """

        parsed = urllib.parse.urlparse(uri)
        if parsed.scheme != "smb":
            raise ValueError(f"Invalid SMB URI: {uri}")
        server = parsed.hostname
        if not server:
            raise ValueError(f"Could not parse server from SMB URI: {uri}")
        parts = parsed.path.strip("/").split("/", 1)
        if not parts or parts[0] == "":
            raise ValueError(f"Could not parse share from SMB URI: {uri}")
        share = parts[0] if parts else ""
        subpath = parts[1] if len(parts) > 1 else ""
        return {"server": server, "share": share, "subpath": subpath}

    def _compute_subpath(self, requested_url: str, actual_url: str) -> str:
        """Computes the subpath within the share by comparing the requested SMB URL and the actual mounted SMB URL."""

        req = self._split_smb(requested_url)
        act = self._split_smb(actual_url)

        # Normalize for comparison
        if req["server"].casefold() != act["server"].casefold():
            raise ValueError(
                f"Server mismatch: requested '{req['server']}' vs actual '{act['server']}'"
            )

        if req["share"].casefold() != act["share"].casefold():
            raise ValueError(
                f"Share mismatch: requested '{req['share']}' vs actual '{act['share']}'"
            )

        # The remaining part is the subpath
        return req["subpath"]

    def _mount(self, path: str, label: str, is_persistent: bool) -> None:
        """Mounts the given network path."""

        logger.info(f"Mounting '{path}' as '{label}' (persistent={is_persistent})")
        drives_dir = Path("~", "Drives").expanduser()
        if not drives_dir.is_dir():
            drives_dir.mkdir()

        # Mount the drive
        smb_url = self._unc_to_smb(path)
        gvfs_file = Gio.File.new_for_uri(smb_url)

        loop = GLib.MainLoop()
        result_holder: dict[str, Optional[BaseException | bool]] = {"error": None, "done": False}

        def mount_done(source, result, user_data):  # ignore[no-untyped-def]
            try:
                source.mount_enclosing_volume_finish(result)
                logger.info(f"Mount operation for '{smb_url}' completed successfully")
            except BaseException as e:
                logger.error(f"Error mounting SMB URL '{smb_url}': {str(e)}")
                result_holder["error"] = e
            finally:
                result_holder["done"] = True
                loop.quit()

        def on_timeout() -> bool:
            if not result_holder["done"]:
                logger.error(f"Mount operation for '{smb_url}' timed out")
                result_holder["error"] = TimeoutError(
                    f"Mount operation for '{smb_url}' timed out"
                )
                loop.quit()
            return False  # Stop the timeout

        gvfs_file.mount_enclosing_volume(
            Gio.MountMountFlags.NONE, None, None, mount_done, None
        )

        GLib.timeout_add_seconds(
            60, on_timeout
        )  # Set a timeout for the mount operation
        loop.run()

        if result_holder["error"]:
            if not isinstance(result_holder["error"], GLib.Error):
                raise result_holder["error"]
            if result_holder["error"].code == Gio.IOErrorEnum.ALREADY_MOUNTED:
                logger.warning(f"SMB URL '{smb_url}' is already mounted")
            else:
                raise result_holder["error"]

        # Wait for the mount to appear in gvfs
        mount_point = None
        gvfs_mount = gvfs_file.find_enclosing_mount(None)
        if gvfs_mount:
            path = Path(gvfs_mount.get_root().get_path())
            wait_time = 10  # seconds
            step = 0.1  # 100 ms
            i = wait_time / step
            while i > 0:
                try:
                    if path.is_dir():
                        mount_point = path
                        logger.info(f"Mount point found for '{smb_url}'")
                        break
                except OSError as e:
                    if e.errno == 5:  # I/O error, often happens when the mount is not fully ready
                        logger.warning(f"OSError no 5 waiting for mount: {path}")
                        pass
                    elif e.errno == 22:  # Invalid argument, can happen if the path is not yet fully available
                        logger.error(f"OSError no 22 waiting for mount: {path}. The mount is probably broken.")
                        pass
                    else:
                        logger.error(f"Error checking mount point for '{smb_url}': {str(e)}")
                        raise e
                i -= 1
                time.sleep(step)

        if not mount_point:
            raise ValueError(
                f"Mount point '{mount_point}' not found after mounting '{smb_url}'"
            )

        # Calculate subpath
        subpath = self._compute_subpath(smb_url, gvfs_mount.get_root().get_uri())

        # Full path to the subfolder if specified
        if subpath and len(subpath) > 0:
            mount_point = Path(mount_point, subpath)
        if not mount_point.exists():
            raise ValueError(
                f"Mount point '{mount_point}' does not exist after mounting '{smb_url}'"
            )

        # Handle the symlink
        symlink_path = drives_dir / label

        if symlink_path.exists():
            if (
                symlink_path.is_symlink()
                and symlink_path.resolve().as_posix() == mount_point.as_posix()
            ):
                logger.info(
                    f"Symlink '{symlink_path}' already exists and points to the correct mount point '{mount_point}'"
                )
                return
            elif symlink_path.is_symlink():
                logger.warning(
                    f"Symlink '{symlink_path}' already exists but does not point to the correct mount point. Removing it."
                )
                symlink_path.unlink()
            else:
                raise ValueError(
                    f"Path '{symlink_path}' already exists and is not a symlink. Cannot create symlink for drive '{label}'"
                )

        symlink_path.symlink_to(mount_point)
        logger.info(
            f"Created symlink '{symlink_path}' pointing to mount point '{mount_point}'"
        )

    def _unmount(self, path: str, label: str) -> None:
        """Unmounts the given network path."""

        logger.info(f"Unmounting '{path}'")
        drives_dir = Path("~", "Drives").expanduser()
        smb_url = self._unc_to_smb(path)

        gvfs_file = Gio.File.new_for_uri(smb_url)
        mount_point = None
        gvfs_mount = None
        try:
            gvfs_mount = gvfs_file.find_enclosing_mount(None)
        except GLib.Error as e:
            if e.code == Gio.IOErrorEnum.NOT_MOUNTED:
                logger.warning(f"SMB URL '{smb_url}' is not mounted according to gvfs")
            else:
                logger.error(f"Error checking mount for SMB URL '{smb_url}': {str(e)}")
                raise e

        symlink = None
        sym_count = 0
        if gvfs_mount:
            mount_point = Path(gvfs_mount.get_root().get_path())
            logger.info(f"Found mount point for '{smb_url}': '{mount_point}'")

            # Find subpath
            subpath = self._compute_subpath(smb_url, gvfs_mount.get_root().get_uri())

            # Find the corresponding symlink prefix and check if it's the last one to use the mount
            symlink_prefix = Path(drives_dir, subpath)
            for entry in drives_dir.iterdir():
                if entry.is_symlink() and entry.resolve().as_posix().startswith(
                    mount_point.as_posix()
                ):
                    if entry.as_posix().startswith(symlink_prefix.as_posix()):
                        symlink = entry
                        logger.info(f"Found symlink: '{entry}'")
                    else:
                        sym_count += 1
        else:
            subpath = label
            symlink_prefix = Path(drives_dir, subpath)
            if symlink_prefix.exists() and symlink_prefix.is_symlink():
                symlink = symlink_prefix
                logger.info(
                    f"Found symlink for '{label}' without gvfs mount: '{symlink}'"
                )

        # Unmount only if there are no other symlinks pointing to the mount point
        if gvfs_mount and sym_count == 0:
            loop = GLib.MainLoop()
            result_holder = {"error": None, "done": False}

            def done_cb(source, result, user_data):  # ignore[no-untyped-def]
                try:
                    source.unmount_with_operation_finish(result)
                    logger.info(
                        f"Unmount operation for '{smb_url}' completed successfully"
                    )
                except BaseException as e:
                    logger.error(f"Error unmounting SMB URL '{smb_url}': {str(e)}")
                    result_holder["error"] = e
                finally:
                    result_holder["done"] = True
                    loop.quit()

            def on_timeout() -> bool:
                if not result_holder["done"]:
                    logger.error(f"Unmount operation for '{smb_url}' timed out")
                    result_holder["error"] = TimeoutError(
                        f"Unmount operation for '{smb_url}' timed out"
                    )
                    loop.quit()
                return False  # Stop the timeout

            gvfs_mount.unmount_with_operation(
                Gio.MountUnmountFlags.NONE, None, None, done_cb, None
            )

            GLib.timeout_add_seconds(
                15, on_timeout
            )  # Set a timeout for the unmount operation
            loop.run()
            if result_holder["error"]:
                if not isinstance(result_holder["error"], GLib.Error):
                    raise result_holder["error"]
                if result_holder["error"].code == Gio.IOErrorEnum.NOT_MOUNTED:
                    logger.warning(
                        f"SMB URL '{smb_url}' is not mounted according to gvfs"
                    )
                else:
                    raise result_holder["error"]
        else:
            logger.warning(
                f"Not unmounting SMB URL '{smb_url}' because there are still {sym_count} symlinks pointing to it"
            )

        # Remove the symlink if it exists
        if symlink and symlink.is_symlink():
            symlink.unlink()
            logger.info(f"Removed symlink '{symlink}'")
        else:
            logger.warning(
                f"Symlink for '{symlink_prefix}' not found or not a symlink. Cannot remove it."
            )

    def _process_folder_xml(self, xml_file: Path) -> None:
        """Processes a Folders.xml file and applies the specified folder actions."""

        # Parse XML
        tree = ET.parse(xml_file)
        root = tree.getroot()
        for folder in root.findall("Folder"):
            name = folder.get("name")
            if not name:
                raise ValueError(f"Folder element missing 'name' attribute in '{xml_file}'")
            name = self._expand_var(name)

            # Make sure this is supposed to be ran in the user context
            if folder.get("userContext") != "1":
                logger.warning(
                    f"Only supporting Folder actions ran within the user context. Skipping '{name}'"
                )
                return

            # Make sure there are no weird attributes
            is_hidden = folder.get("hidden") == "1"
            is_archive = folder.get("archive") == "1"
            if is_hidden or is_archive:
                logger.warning(
                    f"Unsupported Folder attributes hidden='{is_hidden}' archive='{is_archive}' for '{name}'. Skipping."
                )
                return

            props = folder.find("Properties")
            if props is None:
                raise ValueError(f"Folder element missing 'Properties' element in '{xml_file}' for '{name}'")
            action = props.get("action")
            if action is None:
                raise ValueError(f"Folder Properties missing 'action' attribute in '{xml_file}' for '{name}'")
            path = props.get("path")
            if path is None:
                raise ValueError(f"Folder Properties missing 'path' attribute in '{xml_file}' for '{name}'")
            path = self._expand_var(path)
            if action in ("C", "U"):
                self._create_folder(path)
            elif action == "D":
                self._delete_folder(path)
            elif action == "R":
                self._delete_folder(path)
                self._create_folder(path)
            else:
                logger.warning(
                    f"Unsupported Folder action='{action}' for '{name}'. Skipping."
                )
                return

    def _smb_exists(self, path: str) -> bool:
        """Checks if the given SMB path exists."""

        try:
            smbclient.stat(path)
            return True
        except SMBOSError as e:
            if e.ntstatus == NtStatus.STATUS_OBJECT_NAME_NOT_FOUND:
                return False
            else:
                logger.error(f"Error checking existence of UNC path '{path}': {e}")
                raise e

    def _create_folder(self, path: str) -> None:
        """Creates a folder at the given path."""

        # Check if it's a UNC path
        if path.startswith("\\\\"):
            logger.info(f"Creating UNC folder '{path}'")
            # Extract server portion
            server = path.split("\\")[2]
            os.environ["KRB5CCNAME"] = self.cur_user.kerberos_cache
            smbclient.register_session(server)
            if not self._smb_exists(path):
                smbclient.makedirs(path)
                logger.info(f"Created UNC folder '{path}'")
            else:
                logger.info(f"UNC folder '{path}' already exists")
            smbclient.delete_session(server)
            return
        # Check if starts with a drive letter
        elif re.match(r"^[a-zA-Z]:\\", path):
            logger.warning(f"Skipping creation of drive-letter-based path '{path}'")
            return
        else:
            logger.warning(f"Unsupported path format '{path}'. Skipping.")
            return

    def _delete_folder(self, path: str) -> None:
        """Deletes a folder at the given path."""

        # Check if it's a UNC path
        if path.startswith("\\\\"):
            logger.info(f"Creating UNC folder '{path}'")
            # Extract server portion
            server = path.split("\\")[2]
            os.environ["KRB5CCNAME"] = self.cur_user.kerberos_cache
            smbclient.register_session(server)
            if self._smb_exists(path):
                smbclient.rmdir(path)
                logger.info(f"Deleted UNC folder '{path}'")
            else:
                logger.info(f"UNC folder '{path}' already deleted")
            smbclient.delete_session(server)
            return
        # Check if starts with a drive letter
        elif re.match(r"^[a-zA-Z]:\\", path):
            logger.warning(f"Skipping creation of drive-letter-based path '{path}'")
            return
        else:
            logger.warning(f"Unsupported path format '{path}'. Skipping.")
            return

    def _expand_var(self, var: str) -> str:
        """Expands environment variables in the given string."""
        var = var.replace(r"%LogonUser%", self.cur_user.username)
        return var


class DC:
    """Represents the Domain Controller and provides methods to connect to it and retrieve necessary information."""

    def __init__(self) -> None:
        """Initializes the DC object by retrieving the domain and closest DC information."""

        self.domain = self.__get_domain()
        self.dc = self.__get_closest_dc()
        self.ldap: Optional[MyLdap] = None

    def is_valid_fqdn(self, fqdn: str) -> bool:
        """Validates if the given string is a valid Fully Qualified Domain Name (FQDN) according to RFC 1035."""

        # RFC 1035: labels 1-63 chars, total <= 253, only a-z0-9- (no _), no leading/trailing hyphen
        fqdn_regex = re.compile(
            r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*\.?$"
        )
        return bool(fqdn_regex.match(fqdn))

    def is_valid_ip(self, ip: str) -> bool:
        """Validates if the given string is a valid IPv4 address."""

        try:
            ipaddress.IPv4Address(ip)
            return True
        except ipaddress.AddressValueError:
            return False

    def __get_domain(self) -> str:
        """Retrieves the AD domain name."""

        domain = subprocess.run(
            ["realm", "list", "--name-only"], check=True, capture_output=True, text=True
        ).stdout.strip()
        if not self.is_valid_fqdn(domain):
            raise ValueError(f"Invalid domain name: {domain}")
        logger.debug(f"Retrieved domain: {domain}")
        return domain

    def __get_closest_dc(self) -> str:
        """Retrieves the closest Domain Controller (DC) for the domain."""

        # Retrieve the list of DCs for the domain using DNS SRV records
        query = ["host", "-t", "SRV", f"_ldap._tcp.{self.domain}"]
        result = subprocess.run(
            query, check=True, capture_output=True, text=True
        ).stdout.splitlines()
        dc_list = []
        for line in result:
            if "SRV" in line:
                parts = line.split()
                if len(parts) >= 4:
                    dc = parts[-1].rstrip(".").strip()
                    if self.is_valid_fqdn(dc):
                        logger.debug(f"Found DC: {dc}")
                        dc_list.append(dc)
                    else:
                        logger.warning(f"Invalid DC FQDN found in SRV record: {dc}")
        if len(dc_list) < 1:
            raise ValueError(f"No valid DCs found for domain {self.domain}")

        # Retrieve the local default interface
        query = ["ip", "route", "get", "1"]
        result2 = subprocess.run(
            query, check=True, capture_output=True, text=True
        ).stdout.strip()
        local_interface = None
        parts = result2.split()
        for i in range(len(parts)):
            if parts[i] == "dev" and i + 1 < len(parts):
                local_interface = parts[i + 1].strip()
                logger.debug(f"Local default route interface: {local_interface}")
                break
        if local_interface is None or len(local_interface) < 1:
            raise ValueError("Could not determine local default route interface")

        # Retrieve IP and netmask for that interface
        query = ["ip", "-o", "-f", "inet", "addr", "show", "dev", local_interface]
        result3 = subprocess.run(
            query, check=True, capture_output=True, text=True
        ).stdout.strip()
        ip_address = None
        netmask = None
        parts = result3.split()
        for i in range(len(parts)):
            if parts[i] == "inet" and i + 1 < len(parts):
                ip_address, netmask = parts[i + 1].split("/")
                logger.debug(f"Local IP address: {ip_address}, Netmask: {netmask}")
                break
        if ip_address is None or not self.is_valid_ip(ip_address):
            raise ValueError("Could not determine local IP address and netmask")
        if (
            netmask is None
            or not netmask.isdigit()
            or int(netmask) < 1
            or int(netmask) > 32
        ):
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

    def connect(self) -> None:
        """Establishes an LDAP connection to the DC using GSSAPI authentication."""

        server = Server(f"ldap://{self.dc}", get_info=ALL)
        conn = Connection(server, authentication=SASL, sasl_mechanism=GSSAPI)
        try:
            conn.bind()
        except GSSError as e:
            if KRB5KRB_AP_ERR_TKT_EXPIRED == e.min_code:
                logger.error(
                    "Kerberos ticket expired. Please renew your ticket with 'kinit' and try again."
                )
                raise e
            else:
                raise e

        self.ldap = MyLdap(ldap_server=server, ldap_session=conn)


# Hardcoded constants
KRB5KRB_AP_ERR_TKT_EXPIRED = 2529638944

if __name__ == "__main__":
    logger.info(f"Starting AD Drive Mount for: {env.get('USER')}")
    mount_main()
    logger.info("Finished AD Drive Mount")
