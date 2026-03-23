_:
{
  programs = {
    nixfmt.enable = true;

    prettier = {
      enable = true;
      includes = [ "*.md" ];
    };

    shfmt = {
      enable = true;
      indent_size = 2;
    };
  };

  settings.global.excludes = [
    ".github/**"
  ];
}
