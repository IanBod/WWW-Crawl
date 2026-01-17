package WWW::Crawl::Auto;

use strict;
use warnings;

use parent 'WWW::Crawl';

use URI;
use WWW::Crawl::Chromium;

our $VERSION = '0.4';
# $VERSION = eval $VERSION;

sub new {
    my $class = shift;
    my %attrs = @_;

    $attrs{'auto_min_bytes'} //= 512;

    my $self = $class->SUPER::new(%attrs);

    $self->{'_chromium'} = WWW::Crawl::Chromium->new(%attrs);
    $self->{'_mode_by_authority'} = {};
    $self->{'_force_chromium'} = _normalize_host_list($attrs{'force_chromium'});
    $self->{'_force_http'} = _normalize_host_list($attrs{'force_http'});

    return $self;
}

sub _fetch_page {
    my ($self, $url) = @_;

    my $authority = _authority_for($url);

    if ($self->{'_force_chromium'}{$authority}) {
        $self->{'_mode_by_authority'}{$authority} = 'chromium';
        return $self->{'_chromium'}->_fetch_page($url);
    }
    if ($self->{'_force_http'}{$authority}) {
        $self->{'_mode_by_authority'}{$authority} = 'http';
        return $self->SUPER::_fetch_page($url);
    }

    my $mode = $self->{'_mode_by_authority'}{$authority};
    if ($mode && $mode eq 'chromium') {
        return $self->{'_chromium'}->_fetch_page($url);
    }
    if ($mode && $mode eq 'http') {
        return $self->SUPER::_fetch_page($url);
    }

    my $resp = $self->SUPER::_fetch_page($url);
    if ($resp->{'success'}) {
        if ($self->_should_use_chromium($url, $resp)) {
            my $chromium_resp = $self->{'_chromium'}->_fetch_page($url);
            if ($chromium_resp->{'success'}) {
                $self->{'_mode_by_authority'}{$authority} = 'chromium';
                return $chromium_resp;
            }
        }
        $self->{'_mode_by_authority'}{$authority} = 'http';
        return $resp;
    }

    if ($resp->{'status'} && $resp->{'status'} == 404) {
        $self->{'_mode_by_authority'}{$authority} = 'http';
        return $resp;
    }

    my $chromium_resp = $self->{'_chromium'}->_fetch_page($url);
    if ($chromium_resp->{'success'}) {
        $self->{'_mode_by_authority'}{$authority} = 'chromium';
        return $chromium_resp;
    }

    return $resp;
}

sub _should_use_chromium {
    my ($self, $url, $resp) = @_;

    if ($self->{'auto_decider'} && ref $self->{'auto_decider'} eq 'CODE') {
        return $self->{'auto_decider'}->($url, $resp, $self) ? 1 : 0;
    }

    my $content = $resp->{'content'} // '';
    return 0 if $content eq '';

    my $headers = $resp->{'headers'} || {};
    my $ctype = $headers->{'content-type'} || $headers->{'Content-Type'} || '';
    if ($ctype ne '' && $ctype !~ m{\btext/html\b}i) {
        return 0;
    }

    return 1 if $content =~ /<noscript[^>]*>.*?(enable javascript|requires javascript|turn on javascript|javascript required)/is;
    return 1 if $content =~ /id\s*=\s*["'](?:app|root|__next|__nuxt|svelte|react-root)["']/i
        && $content !~ /<a\b/i
        && $content !~ /<form\b/i;
    return 1 if length($content) < $self->{'auto_min_bytes'} && $content =~ /<script\b/i;

    return 0;
}

sub _authority_for {
    my ($url) = @_;
    my $uri = URI->new($url);
    return $uri ? ($uri->authority || $url) : $url;
}

sub _normalize_host_list {
    my ($list) = @_;
    return {} unless $list;
    my @hosts = ref $list eq 'ARRAY' ? @$list : ($list);
    my %map = map { $_ => 1 } @hosts;
    return \%map;
}

1;

__END__

=head1 NAME

WWW::Crawl::Auto - Crawl pages and automatically switch between HTTP and Chromium

=head1 VERSION

This documentation refers to WWW::Crawl::Auto version 0.4.

=head1 SYNOPSIS

    use WWW::Crawl::Auto;

    my $crawler = WWW::Crawl::Auto->new(
        chromium_path  => '/usr/bin/chromium',
        auto_min_bytes => 512,
    );

    my @visited = $crawler->crawl('https://example.com', \&process_page);

    sub process_page {
        my $url = shift;
        print "Visited: $url\n";
    }

=head1 DESCRIPTION

C<WWW::Crawl::Auto> uses the C<WWW::Crawl> crawling logic but decides, per
site, whether to fetch pages with C<HTTP::Tiny> or with a headless Chromium.
When a site is detected as dynamic, the crawler switches to Chromium for that
authority for the rest of the crawl.

=head1 OPTIONS

=over 4

=item *

C<force_chromium>: A hostname (or arrayref of hostnames) to always fetch with
Chromium.

=item *

C<force_http>: A hostname (or arrayref of hostnames) to always fetch with
HTTP::Tiny.

=item *

C<auto_min_bytes>: Minimum response size to consider a static page. Defaults
to 512.

=item *

C<auto_decider>: Coderef invoked as C<auto_decider-E<gt>($url, $resp, $self)>
to decide whether Chromium should be used. Return true to use Chromium.

=back

=head1 METHODS

All public methods are inherited from C<WWW::Crawl>.

=head1 AUTHOR

Ian Boddison, C<< <bod at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2023-2026 by Ian Boddison.

This program is released under the following license:

  Perl

=cut
