package Workflow::Job::Event::View::Default::Xml;

use strict;

class Workflow::Job::Event::View::Default::Xml {
    is => 'UR::Object::View::Default::Xml'
};

# shortcut to the base resolve, which gives us everything. 
sub _resolve_default_aspects {
    grep { index($_,'_') != 0 } shift->UR::Object::View::_resolve_default_aspects(@_);
}

1;
