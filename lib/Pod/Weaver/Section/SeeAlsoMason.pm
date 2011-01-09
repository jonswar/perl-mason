package Pod::Weaver::Section::SeeAlsoMason;
use Moose;
with 'Pod::Weaver::Role::Section';

use Moose::Autobox;

# Add "SEE ALSO: Mason"

sub weave_section {
    my ( $self, $document, $input ) = @_;

    $document->children->push(
        Pod::Elemental::Element::Nested->new(
            {
                command  => 'head1',
                content  => 'SEE ALSO',
                children => [
                    Pod::Elemental::Element::Pod5::Ordinary->new( { content => "L<Mason|Mason>" } ),
                ],
            }
        ),
    );
}

no Moose;
1;
