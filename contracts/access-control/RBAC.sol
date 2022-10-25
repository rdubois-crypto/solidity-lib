// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/access-control/IRBAC.sol";

import "../libs/arrays/ArrayHelper.sol";
import "../libs/arrays/SetHelper.sol";

/**
 *  @notice The Role Based Access Control (RBAC) module
 *
 *  This is advanced module that handles role management for huge systems. One can declare specific permissions
 *  for specific resources (contracts) and aggregate them into roles for further assignment to users.
 *
 *  Each user can have multiple roles and each role can manage multiple resources. Each resource can posses a set of
 *  permissions (CREATE, DELETE) that are only valid for that specific resource.
 *
 *  The RBAC model supports antipermissions as well. One can grant antipermissions to users to restrict their access level.
 *  There also is a special wildcard symbol "*" that means "everything". This symbol can be applied either to the
 *  resources or permissions.
 */
abstract contract RBAC is IRBAC, Initializable {
    using StringSet for StringSet.Set;
    using ArrayHelper for string;
    using SetHelper for StringSet.Set;

    string public constant MASTER_ROLE = "MASTER";

    string public constant ALL_RESOURCE = "*";
    string public constant ALL_PERMISSION = "*";

    string public constant CREATE_PERMISSION = "CREATE";
    string public constant READ_PERMISSION = "READ";
    string public constant UPDATE_PERMISSION = "UPDATE";
    string public constant DELETE_PERMISSION = "DELETE";

    string public constant RBAC_RESOURCE = "RBAC";

    mapping(string => mapping(string => StringSet.Set)) private _roleAllowedPermissions;
    mapping(string => mapping(string => StringSet.Set)) private _roleDisallowedPermissions;

    mapping(string => StringSet.Set) private _roleAllowedResources;
    mapping(string => StringSet.Set) private _roleDisallowedResources;

    mapping(address => StringSet.Set) private _userRoles;

    modifier onlyPermission(string memory resource, string memory permission) {
        require(
            hasPermission(msg.sender, resource, permission),
            string(
                abi.encodePacked("RBAC: no ", permission, " permission for resource ", resource)
            )
        );
        _;
    }

    /**
     *  @notice The init function
     */
    function __RBAC_init() internal onlyInitializing {
        _addPermissionsToRole(MASTER_ROLE, ALL_RESOURCE, ALL_PERMISSION.asArray(), true);
    }

    /**
     *  @notice The function to grant roles to a user
     *  @param to the user to grant roles to
     *  @param rolesToGrant roles to grant
     */
    function grantRoles(address to, string[] memory rolesToGrant)
        public
        virtual
        override
        onlyPermission(RBAC_RESOURCE, CREATE_PERMISSION)
    {
        _grantRoles(to, rolesToGrant);
    }

    /**
     *  @notice The function to revoke roles
     *  @param from the user to revoke roles from
     *  @param rolesToRevoke the roles to revoke
     */
    function revokeRoles(address from, string[] memory rolesToRevoke)
        public
        virtual
        override
        onlyPermission(RBAC_RESOURCE, DELETE_PERMISSION)
    {
        _revokeRoles(from, rolesToRevoke);
    }

    /**
     *  @notice The function to add resource permission to role
     *  @param role the role to add permissions to
     *  @param permissionsToAdd the array of resources and permissions to add to the role
     *  @param allowed indicates whether to add permissions to an allowlist or disallowlist
     */
    function addPermissionsToRole(
        string memory role,
        ResourceWithPermissions[] memory permissionsToAdd,
        bool allowed
    ) public virtual override onlyPermission(RBAC_RESOURCE, CREATE_PERMISSION) {
        for (uint256 i = 0; i < permissionsToAdd.length; i++) {
            _addPermissionsToRole(
                role,
                permissionsToAdd[i].resource,
                permissionsToAdd[i].permissions,
                allowed
            );
        }
    }

    /**
     *  @notice The function to remove permissions from role
     *  @param role the role to remove permissions from
     *  @param permissionsToRemove the array of resources and permissions to remove from the role
     *  @param allowed indicates whether to remove permissions from the allowlist or disallowlist
     */
    function removePermissionsFromRole(
        string memory role,
        ResourceWithPermissions[] memory permissionsToRemove,
        bool allowed
    ) public virtual override onlyPermission(RBAC_RESOURCE, DELETE_PERMISSION) {
        for (uint256 i = 0; i < permissionsToRemove.length; i++) {
            _removePermissionsFromRole(
                role,
                permissionsToRemove[i].resource,
                permissionsToRemove[i].permissions,
                allowed
            );
        }
    }

    /**
     *  @notice The function to get the list of user roles
     *  @param who the user
     *  @return roles the roes of the user
     */
    function getUserRoles(address who) public view override returns (string[] memory roles) {
        return _userRoles[who].values();
    }

    /**
     *  @notice The function to get the permissions of the role
     *  @param role the role
     *  @return allowed the list of allowed permissions of the role
     *  @return disallowed the list of disallowed permissions of the role
     */
    function getRolePermissions(string memory role)
        public
        view
        override
        returns (
            ResourceWithPermissions[] memory allowed,
            ResourceWithPermissions[] memory disallowed
        )
    {
        allowed = new ResourceWithPermissions[](_roleAllowedResources[role].length());
        disallowed = new ResourceWithPermissions[](_roleDisallowedResources[role].length());

        for (uint256 i = 0; i < allowed.length; i++) {
            allowed[i].resource = _roleAllowedResources[role].at(i);
            allowed[i].permissions = _roleAllowedPermissions[role][allowed[i].resource].values();
        }

        for (uint256 i = 0; i < disallowed.length; i++) {
            disallowed[i].resource = _roleDisallowedResources[role].at(i);
            disallowed[i].permissions = _roleDisallowedPermissions[role][disallowed[i].resource]
                .values();
        }
    }

    /**
     *  @notice The function to check the user's possesion of the role
     *  @param who the user
     *  @param resource the resource the user has to have the permission of
     *  @param permission the permission the user has to have
     *  @return true if user has the permission, false otherwise
     */
    function hasPermission(
        address who,
        string memory resource,
        string memory permission
    ) public view override returns (bool) {
        StringSet.Set storage roles = _userRoles[who];

        uint256 length = roles.length();
        bool isAllowed;

        for (uint256 i = 0; i < length; i++) {
            string memory role = roles.at(i);

            StringSet.Set storage allDisallowed = _roleDisallowedPermissions[role][ALL_RESOURCE];
            StringSet.Set storage allAllowed = _roleAllowedPermissions[role][ALL_RESOURCE];

            StringSet.Set storage disallowed = _roleDisallowedPermissions[role][resource];
            StringSet.Set storage allowed = _roleAllowedPermissions[role][resource];

            if (
                allDisallowed.contains(ALL_PERMISSION) ||
                allDisallowed.contains(permission) ||
                disallowed.contains(ALL_PERMISSION) ||
                disallowed.contains(permission)
            ) {
                return false;
            }

            if (
                allAllowed.contains(ALL_PERMISSION) ||
                allAllowed.contains(permission) ||
                allowed.contains(ALL_PERMISSION) ||
                allowed.contains(permission)
            ) {
                isAllowed = true;
            }
        }

        return isAllowed;
    }

    /**
     *  @notice The internal function to grant roles
     *  @param to the user to grant roles to
     *  @param rolesToGrant the roles to grant
     */
    function _grantRoles(address to, string[] memory rolesToGrant) internal {
        _userRoles[to].add(rolesToGrant);
    }

    /**
     *  @notice The internal function to revoke roles
     *  @param from the user to revoke roles from
     *  @param rolesToRevoke the roles to revoke
     */
    function _revokeRoles(address from, string[] memory rolesToRevoke) internal {
        _userRoles[from].remove(rolesToRevoke);
    }

    /**
     *  @notice The internal function to add permission to the role
     *  @param role the role to add permissions to
     *  @param resourceToAdd the resource to which the permissions belong
     *  @param permissionsToAdd the permissions of the resource
     *  @param allowed whether to add permissions to the allowlist or the disallowlist
     */
    function _addPermissionsToRole(
        string memory role,
        string memory resourceToAdd,
        string[] memory permissionsToAdd,
        bool allowed
    ) internal {
        StringSet.Set storage resources = allowed
            ? _roleAllowedResources[role]
            : _roleDisallowedResources[role];

        StringSet.Set storage permissions = allowed
            ? _roleAllowedPermissions[role][resourceToAdd]
            : _roleDisallowedPermissions[role][resourceToAdd];

        permissions.add(permissionsToAdd);
        resources.add(resourceToAdd);
    }

    /**
     *  @notice The internal function to remove permissions from the role
     *  @param role the role to remove permissions from
     *  @param resourceToRemove the resource to which the permissions belong
     *  @param permissionsToRemove the permissions of the resource
     *  @param allowed whether to remove permissions from the allowlist or the disallowlist
     */
    function _removePermissionsFromRole(
        string memory role,
        string memory resourceToRemove,
        string[] memory permissionsToRemove,
        bool allowed
    ) internal {
        StringSet.Set storage resources = allowed
            ? _roleAllowedResources[role]
            : _roleDisallowedResources[role];

        StringSet.Set storage permissions = allowed
            ? _roleAllowedPermissions[role][resourceToRemove]
            : _roleDisallowedPermissions[role][resourceToRemove];

        permissions.remove(permissionsToRemove);

        if (permissions.length() == 0) {
            resources.remove(resourceToRemove);
        }
    }
}