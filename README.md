# jamfSccm
JAMF Software Casper - SCCM Plugin UDA Adapter

This script is intended for administrators utilizing JAMF Software's Casper suite to manage Macs in their environment, and using their Casper-to-SCCM plugin for getting devices into their SCCM environment. This script's function is to map AD users' tied to Casper OSX devices to SCCM's User Device Affinity (UDA) functionality. It will parse through the users and devices in Casper and appropriately map them to UDA in SCCM, including making use of its expiration dates and other criteria. This is fairly essential for any enterprise utilizing UDA for day-to-day operations in SCCM, and also using JAMF's software.

Documentation is included in the code for simply inserting the SQL server, SCCM site code and SCCM server that is intended to manage the endpoints. It is best utilized by simply setting up a Scheduled Task to execute the PowerShell script, and ensuring the run-as user has both read access to the SCCM database as well as administrative access to the WMI namespace.

This has been tested in SCCM 2012 R2 SP1 U8 and up.

UPDATED 3/8/16: Added in a scrub for old UDA records for Mac devices if end-users or anyone else had manually put them into the SCCM console. This would interfere with the script's ability to sync up the UDA with JSS usernames properly.
UPDATED 1/25/17: This has now been tested in SCCM CB 1511, 1602 and 1610.
UPDATED 6/2/17: Tested successfully in 1706.
UPDATE 12/28/17: Tested successfully in 1710.
