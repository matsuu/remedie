package Remedie::Server::RPC::Collection;
use Moose;

BEGIN { extends 'Remedie::Server::RPC' }

__PACKAGE__->meta->make_immutable;

no Moose;

use Remedie;
use Remedie::DB::Channel;
use DateTime;
use DateTime::Format::Mail;
use Encode;
use Template;
use XML::OPML::LibXML;
use Plagger::Util;

sub opml {
    my($self, $req, $res) = @_;

    my $channels = Remedie::DB::Channel::Manager->get_channels();

    my $stash = {
        channels => $channels,
        now => DateTime::Format::Mail->format_datetime( DateTime->now ),
        version => Remedie->VERSION,
    };

    my $tt = Template->new;
    $tt->process(\<<TEMPLATE, $stash, \my $out) or die $tt->error;
<?xml version="1.0" encoding="utf-8"?>
<!-- OPML generated by Remedie [% version %] -->
<opml version="2.0">
<head>
<title>remedie_subscription.opml</title>
<dateCreated>[% now %]</dateCreated>
<docs>http://www.opml.org/spec2</docs>
</head>
<body>
<outline text="Subscriptions">
[% FOREACH channel = channels -%]
<outline type="rss" text="[% channel.name | html %]"[% IF channel.props.link %] htmlUrl="[% channel.props.link | html %]"[% END %] xmlUrl="[% channel.ident | html %]" />
[% END -%]
</outline>
</body>
</opml>
TEMPLATE

    $res->status(200);
    $res->content_type("text/xml; charset=utf-8");
    $res->body( encode_utf8($out) );

    return { success => 1 };
}

# Don't set :POST because file upload can't set X-Remedie-Client header
sub import_opml {
    my($self, $req, $res) = @_;

    my $upload = $req->uploads->{file};
    my $parser = XML::OPML::LibXML->new;
    my $doc = $parser->parse_fh($upload->fh);

    my @channel_ids;
    my $callback = sub {
        my $outline = shift;
        return unless $outline->xml_url;

        my $channel = Remedie::DB::Channel->new;
        $channel->ident($outline->xml_url);
        $channel->type( Remedie::DB::Channel->TYPE_FEED );
        $channel->name($outline->title || $outline->text);
        $channel->parent(0); # TODO support tree

        eval {
            $channel->save;
            push @channel_ids, $channel->id;
        }; # ignore dupe
    };
    $doc->walkdown($callback);

    $res->content_type('text/plain');
    $res->body( join(",", @channel_ids) );

    return { success => 1 };
}

1;
