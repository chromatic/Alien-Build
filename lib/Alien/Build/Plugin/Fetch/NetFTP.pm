package Alien::Build::Plugin::Fetch::NetFTP;

use strict;
use warnings;
use Alien::Build::Plugin;
use Carp ();
use File::Temp ();
use Path::Tiny qw( path );

# ABSTRACT: Net::FTP plugin for fetching files
# VERSION

=head1 SYNOPSIS

 use alienfile;
 plugin 'Fetch::NetFTP' => (
   url => 'ftp://ftp.gnu.org/gnu/make',
 );

=head1 DESCRIPTION

Note: in most case you will want to use L<Alien::Build::Plugin::Download::Negotiate>
instead.  It picks the appropriate fetch plugin based on your platform and environment.
In some cases you may need to use this plugin directly instead.

This fetch plugin fetches files and directory listings via the C<ftp>, protocol using
L<Net::FTP>.

=head1 PROPERTIES

=head2 url

The initial URL to fetch.  This may be a directory or the final file.

=cut

has '+url' => sub { Carp::croak "url is a required property" };

=head2 ssl

This property is for compatibility with other fetch plugins, but is not used.

=cut

has ssl => 0;

=head2 passive

If set to true, try passive mode FIRST.  By default it will try an active mode, then
passive mode.

=cut

has passive => 0;

sub init
{
  my($self, $meta) = @_;

  $meta->add_requires('share' => 'Net::FTP' => 0 );
  $meta->add_requires('share' => 'URI' => 0 );
  $meta->add_requires('share' => 'Alien::Build::Plugin::Fetch::NetFTP' => '0.61')
    if $self->passive;

  $meta->register_hook( fetch => sub {
    my($build, $url) = @_;
    $url ||= $self->url;
    
    $url = URI->new($url);
    
    $build->log("trying passive mode FTP first") if $self->passive;
    my $ftp = _ftp_connect($url, $self->passive);

    my $path = $url->path;

    unless($path =~ m!/$!)
    {
      my(@parts) = split '/', $path;
      my $filename = pop @parts;
      my $dir      = join '/', @parts;
      
      my $path = eval {
        $ftp->cwd($dir) or die;
        my $tdir = File::Temp::tempdir( CLEANUP => 1);
        my $path = path("$tdir/$filename")->stringify;
        
        unless(eval { $ftp->get($filename, $path) }) # NAT problem? try to use passive mode
        {
          $ftp->quit;
          
          $build->log("switching to @{[ $self->passive ? 'active' : 'passive' ]} mode");
          $ftp = _ftp_connect($url, !$self->passive);
          
          $ftp->cwd($dir) or die;
          
          $ftp->get($filename, $path) or die;
        }
        
        $path;
      };
      
      if(defined $path)
      {
        return {
          type     => 'file',
          filename => $filename,
          path     => $path,
        };
      }
      
      $path .= "/";
    }
    
    $ftp->quit;
    $ftp = _ftp_connect($url, $self->passive);
    $ftp->cwd($path) or die "unable to fetch $url as either a directory or file";
    
    my $list = eval { $ftp->ls };
    unless(defined $list) # NAT problem? try to use passive mode
    {
      $ftp->quit;
      
      $build->log("switching to @{[ $self->passive ? 'active' : 'passive' ]} mode");
      $ftp = _ftp_connect($url, !$self->passive);
      
      $ftp->cwd($path) or die "unable to fetch $url as either a directory or file";
      
      $list = $ftp->ls;
      
      die "cannot list directory $path on $url" unless defined $list;
    }
    
    die "no files found at $url" unless @$list;

    $path .= '/' unless $path =~ /\/$/;
    
    return {
      type => 'list',
      list => [
        map {
          my $filename = $_;
          my $furl = $url->clone;
          $furl->path($path . $filename);
          my %h = (
            filename => $filename,
            url      => $furl->as_string,
          );
          \%h;
        } sort @$list,
      ],
    };
    
  });

  $self;
}

sub _ftp_connect {
  my $url = shift;
  my $is_passive = shift || 0;

  Alien::Build->log("is_passive = $is_passive");
  
  my $ftp = Net::FTP->new(
    $url->host, Port =>$url->port, Passive =>$is_passive,
  ) or die "error fetching $url: $@";
  
  $ftp->login($url->user, $url->password)
    or die "error on login $url: @{[ $ftp->message ]}";
  
  $ftp->binary;
  
  $ftp;
}

1;

=head1 SEE ALSO

L<Alien::Build::Plugin::Download::Negotiate>, L<Alien::Build>, L<alienfile>, L<Alien::Build::MM>, L<Alien>

=cut
