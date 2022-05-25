
Guide for Service Administrators
================================

This documentation covers some of the aspects of the GEOPM Service
that are important to system administrators.  These include how the
GEOPM Service is integrated with the Linux OS, which directories are
created and modified by the GEOPM Service, how the files in those
directories are used, and a command line tool to configure the GEOPM
Service.  Additional information is available on other pages:

- `Install Guide <install.html>`_
- `Security Guide <security.html>`_


Linux Integration
-----------------

The GEOPM service integrates with the Linux OS through Systemd as a
unit that is installed with the geopm-service RPM.  The ``sytemctl``
command can be used to interact with the ``geopm`` Systemd Unit.


GEOPM Service Files
-------------------

In addition to the files provided by the installation packages, the
GEOPM service may create and modify files at run-time.  These include
files in ``/etc/geopm-service`` that control access settings and files
in ``/run/geopm-service`` that track information about clients that
are actively using the service.

All files and directories within ``/etc/geopm-service`` or
``/run/geopm-service`` are created by the GEOPM Service with
restricted access permissions and root ownership.  The GEOPM Service
will not read any file or directory if they are modified to have more
permissive access restrictions, non-root ownership, or if they are
replaced by a symbolic link or other non-regular file.  If these
checks fail, the file or directory will be renamed to include a UUID
string and a warning is printed in the syslog.  These renamed files or
directories enable an administrator to perform an investigation into
problem, but they will not be used by the GEOPM Service in any way.

It is recommended that these GEOPM Service system files are always
manipulated using GEOPM tools like ``geopmaccess``, however, any
administrator that manipulates the GEOPM system files without using a
GEOPM interface should be aware of the permission and ownership
requirements for these files.


Configuring Access Lists
------------------------

The `geopmaccess(1) <geopmaccess.1.html>`_ command line tool is used
by a system administrator to manage access to the features provided by
the GEOPM Service.  The GEOPM Service does not allow read or write
access for any non-root user until the system administrator explicitly
configures the service using the ``geopmaccess`` command line tool.
This command line interface allows the administrator to set access
permissions for all users, and may extend these default privileges for
specific Unix groups.
