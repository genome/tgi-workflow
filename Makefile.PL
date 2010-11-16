use inc::Module::Install;

name 'Cord';
author 'Eric Clark <eclark@wustl.edu>';
version_from 'lib/Cord.pm';
license 'perl';

requires 'UR' => 0;
requires 'POE' => '';
auto_install;

WriteAll;
