
GEOPM Service Tutorial
======================


Upstream RHEL and CentOS Package Requirements
---------------------------------------------

.. code-block::

    yum install python3 python3-devel python3-gobject-base



Upstream SLES and OpenSUSE Package Requirements
-----------------------------------------------

.. code-block::

    zypper install python3 python3-devel python3-gobject


Dasbus Requrement
-----------------

The GEOPM service requires a more recent version of dasbus than is
currently packaged by Linux distributions (dasbus version 1.5 or more
recent).  The script located in ``geopm/test/build_dasbus.sh`` can be
executed to create the required RPM based on dasbus version 1.6.  The
script will print how to install the generated RPM upon succesful
completion.


Building and Installing
-----------------------

Support for packaging for CentOS-8 RHEL-8 and SLES-15-SP2 is provided
by the geopm service build system.

.. code-block::

   git clone git@github.com:geopm/geopm.git
   cd geopm
   git checkout geopm-service
   cd service
   ./autogen.sh
   ./configure
   make rpm
   sudo ./test/install_service.sh $(cat VERSION) $USER
