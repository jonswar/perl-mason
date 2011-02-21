package Pod::Weaver::Section::SeeAlsoMason;
use Moose;
use Moose::Autobox;
with 'Pod::Weaver::Role::Section';

# Add "SEE ALSO: Mason"

sub weave_section {
    my ( $self, $document, $input ) = @_;

    my $idc = $input->{pod_document}->children;
    for ( my $i = 0 ; $i < $idc->length ; $i++ ) {
        next unless my $para = $idc->[$i];
        return
          if $para->can('command') && $para->command eq 'head1' && $para->content eq 'SEE ALSO';
    }
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
