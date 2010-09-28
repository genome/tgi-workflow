use inc::Module::Install;

name 'Workflow';
author 'Eric Clark <eclark@wustl.edu>';
version_from 'lib/Workflow.pm';
license 'perl';

build_requires 'Test::More';
requires 'POE' => '';
auto_install;

WriteAll;
