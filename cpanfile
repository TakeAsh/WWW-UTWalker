requires 'Const::Fast';
requires 'Encode';
requires 'File::Share';
requires 'Filesys::DfPortable';
requires 'FindBin::libs';
requires 'Getopt::Long';
requires 'IPC::Cmd';
requires 'List::Util';
requires 'Log::Dispatch';
requires 'Number::Bytes::Human';
requires 'Term::Encoding';
requires 'Time::Piece';
requires 'Try::Tiny';
requires 'YAML::Syck';
requires 'feature';
requires 'perl', '5.010';
requires 'version', '0.77';

on configure => sub {
    requires 'Module::Build::Tiny', '0.035';
};

on test => sub {
    requires 'Test::More';
    requires 'Test::More::UTF8';
};
