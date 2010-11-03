use inc::Module::Install;

name 'Cord';
author 'Eric Clark <eclark@wustl.edu>';
version_from 'lib/Cord.pm';
license 'perl';

build_requires 'Test::More';
requires 'POE' => '';
auto_install;

WriteAll;
