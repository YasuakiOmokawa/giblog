package Giblog::API;

use strict;
use warnings;
use File::Find 'find';
use File::Basename 'dirname', 'basename';
use File::Path 'mkpath';
use Carp 'confess';
use Encode 'encode', 'decode';
use File::Copy 'copy';

sub new {
  my $class = shift;
  
  my $self = {@_};
  
  return bless $self, $class;
}

sub giblog { shift->{giblog} }

sub config { shift->giblog->config }

sub giblog_dir { shift->giblog->giblog_dir };

sub get_proto_dir {
  my ($self, $module_name) = @_;
  
  my $proto_dir = $self->module_rel_file($module_name, 'proto');
  
  return $proto_dir;
}

sub create_website {
  my ($self, $home_dir, $proto_dir) = @_;
  
  unless (defined $home_dir) {
    confess "Website name must be specifed\n";
  }
  
  if (-f $home_dir) {
    confess "Website \"$home_dir\" is already exists\n";
  }
  
  unless (-d $proto_dir) {
    confess "proto diretory can't specified\n";
  }

  # Create website directory
  $self->create_dir($home_dir);

  # Copy command proto files to user directory
  my @files;
  find(
    {
      wanted => sub {
        my $proto_file = $File::Find::name;
        
        # Skip directory
        return unless -f $proto_file;
        
        my $rel_file = $proto_file;
        $rel_file =~ s/^\Q$proto_dir\E[\/|\\]//;
        
        my $user_file = "$home_dir/$rel_file";
        my $user_dir = dirname $user_file;
        mkpath $user_dir;
        
        copy $proto_file, $user_file
          or confess "Can't copy $proto_file to $user_file: $!";
      },
      no_chdir => 1,
    },
    $proto_dir
  );
}

sub run_command {
  my ($self, $command_name, @argv) = @_;
  
  # Command is implemented in command
  my $command_class = "Giblog::Command::$command_name";
  eval "use $command_class;";
  if ($@) {
    confess "Can't load command $command_class:\n$!\n$@";
  }
  my $command = $command_class->new(api => $self);

  $command->run(@argv);
}

sub clear_config {
  my $self = shift;
  
  my $giblog = $self->giblog;
  
  $giblog->{config} = undef;
}

sub read_config {
  my $self = shift;
  
  my $giblog = $self->giblog;
  
  # Read config
  my $config;
  if (defined $giblog->{config}) {
    confess "Config is already loaded";
  }
  
  my $config_file = $self->rel_file('giblog.conf');
  
  my $config_content = $self->slurp_file($config_file);
  
  $config = eval $config_content
    or confess "Can't parse config file \"$config_file\"";
    
  unless (ref $config eq 'HASH') {
    confess "\"$config_file\" must end with hash reference";
  }
  
  $giblog->{config} = $config;
  
  return $config;
}

sub rel_file {
  my ($self, $file) = @_;
  
  my $giblog_dir = $self->giblog->giblog_dir;
  
  if (defined $giblog_dir) {
    return "$giblog_dir/$file";
  }
  else {
    return $file;
  }
}

sub create_dir {
  my ($self, $dir) = @_;
  mkdir $dir
    or confess "Can't create directory \"$dir\": $!";
}

sub create_file {
  my ($self, $file) = @_;
  open my $fh, '>', $file
    or confess "Can't create file \"$file\": $!";
}

sub write_to_file {
  my ($self, $file, $content) = @_;
  open my $fh, '>', $file
    or confess "Can't create file \"$file\": $!";
  
  print $fh encode('UTF-8', $content);
}

sub slurp_file {
  my ($self, $file) = @_;

  open my $fh, '<', $file
    or confess "Can't read file \"$file\": $!";
  
  my $content = do { local $/; <$fh> };
  $content = decode('UTF-8', $content);
  
  return $content;
}

sub module_rel_file {
  my ($self, $module_name, $rel_file) = @_;
  
  my $command_rel_path = $module_name;
  $command_rel_path =~ s/::/\//g;
  $command_rel_path .= '.pm';
  
  my $command_path = $INC{$command_rel_path};
  
  unless ($command_path) {
    confess "Can't get module path because module is not loaded";
  }
  
  my $command_dir = $command_path;
  $command_dir =~ s/\.pm$//;
  
  my $file = "$command_dir/$rel_file";
  
  return $file;
}

sub get_templates_files {
  my $self = shift;

  my $templates_dir = $self->rel_file('templates');

  # Get template files
  my @template_rel_files;
  find(
    {
      wanted => sub {
        my $template_file = $File::Find::name;
        
        # Skip directory
        return unless -f $template_file;

        # Skip common files
        return if $template_file =~ /^\Q$templates_dir\/common/;
        
        my $template_file_base = $_;
        
        # Skip hidden file
        return if $template_file_base =~ /^\./;
        
        my $template_rel_file = $template_file;
        $template_rel_file =~ s/^$templates_dir//;
        $template_rel_file =~ s/^[\\\/]//;
        
        push @template_rel_files, $template_rel_file;
      },
      no_chdir => 1,
    },
    $templates_dir
  );
  
  return \@template_rel_files;
}

sub get_content {
  my ($self, $data) = @_;
  
  my $file = $data->{file};
  
  my $template_file = $self->rel_file("templates/$file");
  my $content = $self->slurp_file($template_file);
  
  $data->{content} = $content;
}

sub write_to_public_file {
  my ($self, $data) = @_;
  
  my $content = $data->{content};
  my $file = $data->{file};
  
  # public file
  my $public_file = $self->rel_file("public/$file");
  my $public_dir = dirname $public_file;
  mkpath $public_dir;
  
  # Write to public file
  $self->write_to_file($public_file, $content);
}

my $inline_elements_re = qr/^<(span|em|strong|abbr|acronym|dfn|q|cite|sup|sub|code|var|kbd|samp|bdo|font|big|small|b|i|s|strike|u|tt|a|label|object|applet|iframe|button|textarea|select|basefont|img|br|input|script|map)\b/;

sub parse_giblog_syntax {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;
  
  my $content = $data->{content};

  # Normalize line break;
  $content =~ s/\x0D\x0A|\x0D|\x0A/\n/g;
  
  # Parse Giblog syntax
  my @lines = split /\n/, $content;
  my $pre_start;
  $content = '';
  my $bread_end;
  for my $line (@lines) {
    my $original_line = $line;
    
    # Pre end
    if ($line =~ m|^</pre\b|) {
      $pre_start = 0;
    }
    
    # Escape >, < in pre tag
    if ($pre_start) {
      $line =~ s/>/&gt;/g;
      $line =~ s/</&lt;/g;
      $content .= "$line\n";
    }
    else {
      # If start with inline tag, wrap p
      if ($line =~ $inline_elements_re) {
        $content .= "<p>\n  $line\n</p>\n";
      }
      # If start with space or tab or not inline tag, it is raw line
      elsif ($line =~ /^[ \t\<]/) {
        $content .= "$line\n";
      }
      # If line have length, wrap p
      else {
        if (length $line) {
          $content .= "<p>\n  $line\n</p>\n";
        }
      }
    }

    # Pre start
    if ($original_line =~ m|^<pre\b|) {
      $pre_start = 1
    }
  }
  
  $data->{content} = $content;
}

sub parse_title {
  my ($self, $data) = @_;
  
  my $config = $self->config;

  my $content = $data->{content};
  
  unless (defined $data->{'title'}) {
    if ($content =~ m|class="title"[^>]*?>([^<]*?)<|) {
      my $title = $1;
      $data->{title} = $title;
    }
  }
}

sub parse_title_from_first_h_tag {
  my ($self, $data) = @_;
  
  my $config = $self->config;

  my $content = $data->{content};
  
  unless (defined $data->{'title'}) {
    if ($content =~ m|<\s*h[1-6]\b[^>]*?>([^<]*?)<|) {
      my $title = $1;
      $data->{title} = $title;
    }
  }
}

sub add_page_link_to_first_h_tag {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};
  
  # Add page link
  my $file = $data->{file};
  my $path;
  if ($file eq 'index.html') {
    $path = '/';
  }
  else {
    $path = "/$file";
  }
  
  $content =~ s|(<\s*h[1-6]\b[^>]*?>)([^<]*?)<|$1<a href="$path">$2</a><|;

  $data->{'content'} = $content;
}

sub add_page_link {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};
  
  # Add page link
  my $file = $data->{file};
  my $path;
  if ($file eq 'index.html') {
    $path = '/';
  }
  else {
    $path = "/$file";
  }
  
  $content =~ s|class="title"[^>]*?>([^<]*?)<|class="title"><a href="$path">$1</a><|;

  $data->{'content'} = $content;
}

sub parse_description {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};
  
  if ($content =~ m|class="description"[^>]*?>([^<]*?)<|) {
    my $description = $1;
    unless (defined $data->{'description'}) {
      $data->{'description'} = $description;
    }
  }
}

sub parse_description_from_first_p_tag {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};
  
  # Create description from first p tag
  unless (defined $data->{'description'}) {
    if ($content =~ m|<\s?p\b[^>]*?>(.*?)<\s?/\s?p\s?>|s) {
      my $description = $1;
      # remove tag
      $description =~ s/<.*?>//g;
      
      # trim space
      $description =~ s/^\s+//;
      $description =~ s/\s+$//;
      
      $data->{'description'} = $description;
    }
  }
}

sub parse_keywords {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};

  # keywords
  if ($content =~ m|class="keywords"[^>]*?>([^<]*?)<|) {
    my $keywords = $1;
    unless (defined $data->{'keywords'}) {
      $data->{'keywords'} = $1;
    }
  }
}

sub parse_first_img_src {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};
  
  # image
  if ($content =~ /<\s*img\b.*?\bsrc\s*=\s*"([^"]*?)"/s) {
    my $image = $1;
    unless (defined $data->{'image'}) {
      $data->{'image'} = $image;
    }
  }
}

sub wrap {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = <<"EOS";
<!DOCTYPE html>
<html>
  <head>
    $data->{meta}
  </head>
  <body>
    <div class="container">
      <div class="header">
        $data->{header}
      </div>
      <div class="main">
        <div class="entry">
          <div class="top">
            $data->{top}
          </div>
          <div class="content">
            $data->{content}
          </div>
          <div class="bottom">
            $data->{bottom}
          </div>
        </div>
        <div class="side">
          $data->{side}
        </div>
      </div>
      <div class="footer">
        $data->{footer}
      </div>
    </div>
  </body>
</html>
EOS
  
  $data->{content} = $content;
}

sub add_meta_title {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;
  
  my $meta = $data->{meta};
  
  # Title
  my $title = $data->{title};
  if (defined $title) {
    $meta .= "\n<title>$title</title>\n";
  }
  
  $data->{meta} = $meta;
}

sub add_meta_description {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;
  
  my $meta = $data->{meta};
  
  # Title
  my $description = $data->{description};
  if (defined $description) {
    $meta .= qq(\n<meta name="description" content="$description">\n);
  }
  
  $data->{meta} = $meta;
}

sub prepare_wrap {
  my ($self, $data) = @_;
  
  my $common_meta_file = $self->rel_file('templates/common/meta.html');
  my $common_meta_content = $self->slurp_file($common_meta_file);
  $data->{meta} = $common_meta_content;

  my $common_header_file = $self->rel_file('templates/common/header.html');
  my $common_header_content = $self->slurp_file($common_header_file);
  $data->{header} = $common_header_content;

  my $common_footer_file = $self->rel_file('templates/common/footer.html');
  my $common_footer_content = $self->slurp_file($common_footer_file);
  $data->{footer} = $common_footer_content;

  my $common_side_file = $self->rel_file('templates/common/side.html');
  my $common_side_content = $self->slurp_file($common_side_file);
  $data->{side} = $common_side_content;

  my $common_top_file = $self->rel_file('templates/common/top.html');
  my $common_top_content = $self->slurp_file($common_top_file);
  $data->{top} = $common_top_content;

  my $common_bottom_file = $self->rel_file('templates/common/bottom.html');
  my $common_bottom_content = $self->slurp_file($common_bottom_file);
  $data->{bottom} = $common_bottom_content;
}

1;

=head1 NAME

Giblog::API - Giblog API

=head1 DESCRIPTION

Giblog::API defines sevral methods to manipulate HTML contents.

=head1 METHODS

=head2 new

  my $api = Giblog::API->new(%params);

Create L<Giblog::API> object.

B<Parameters:>

=over 4

=item * giblog

Set L<Giblog> object.

By C<giblog> method, you can access this parameter.

  my $giblog = $api->giblog;

=back

=head2 config

  my $config = $api->config;

Get Giblog config. This is hash reference.

Config is loaded by C<read_config> method.

If config is not loaded, this method return undef.

=head2 giblog_dir

  my $giblog_dir = $api->giblog_dir;

Get Giblog home directory.

=head2 read_config

  my $config = $api->read_config;

Parse "giblog.conf" in Giblog home directory and return hash reference.

"giblog.conf" must end with correct hash reference.
  
  # giblog.conf
  {
    site_title => 'mysite',
    site_url => 'http://somesite.example',
  }

Otherwise exception occur.

After calling read_config, You can also get config by C<config> method.

=head2 clear_config

  $api->clear_config;

Clear config. Set undef to config.

=head2 get_proto_dir

  my $proto_dir = $api->get_proto_dir($module_name);

Get "proto" directory path corresponding to module name.

If module name is "Giblog::Command::new_foo" and loading path is "lib/Giblog/Command/new_foo.pm", path of "proto" directory is "lib/Giblog/Command/new_foo/proto".

  lib/Giblog/Command/new_foo.pm
                    /new_foo/proto

Module must be loaded. otherwise exception occur.

=head2 create_website

  $api->create_website($website_name, $proto_dir);

ウェブサイト名と、protoディレクトリを指定して、Webサイトを作成します。

ウェブサイト名で指定された名前を持つディレクトリが作成され、その中にprotoディレクトリの中身がコピーされます。

ウェブサイト名は、ファイル名として有効な名前を指定してください。

ウェブサイト名が、指定されない場合は、例外が発生します。

ウェブサイトがすでに存在する場合は、例外が発生します。

protoディレクトリが指定されない場合は、例外が発生します。

=head2 run_command

  $api->run_command($command_name, @args);

コマンド名を指定して、引数を与えてコマンドを実行します。

たとえば、コマンド名が「build」の場合は「Giblog::Command::build」がロードされ、このクラスの「run」メソッドが実行されます。

コマンド名に対応するコマンドクラスがロードできなかった場合は、例外が発生します。

=head2 giblog_dir

  my $giblog_dir = $api->giblog_dir;

Giblogのホームディレクトリを取得します。

=head2 rel_file

  my $file = $api->rel_file('foo/bar');

Giblogのホームディレクトリに、指定された相対パスを結合したパスを返します。

ホームディレクトリが設定されていない場合は、そのまま返します。

=head2 create_dir

  $api->create_dir($dir);

ディレクトリを作成します。

ディレクトリの作成に失敗した場合は、例外が発生します。

=head2 create_file

  $api->create_file($file);

ファイルを作成します。

ファイルの作成に失敗した場合は、例外が発生します。

=head2 write_to_file

=head2 slurp_file

=head2 module_rel_file

=head2 giblog

=head2 get_templates_files

=head2 get_content

=head2 write_to_public_file

=head2 parse_giblog_syntax

=head2 parse_title

=head2 add_page_link

=head2 parse_description

=head2 parse_description_from_first_p_tag

=head2 parse_keywords

=head2 parse_first_img_src

=head2 wrap

=head2 add_meta_title

=head2 add_meta_description

=head2 prepare_wrap
