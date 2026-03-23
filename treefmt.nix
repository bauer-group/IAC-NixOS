{ ... }: {
  # Nix code formatting (RFC-style, officially adopted by the Nix community)
  programs.nixfmt.enable = true;

  # Markdown formatting (docs/)
  programs.prettier = {
    enable = true;
    includes = [ "*.md" ];
  };

  # Shell script formatting
  programs.shfmt = {
    enable = true;
    indent_size = 2;
  };

  # Exclude workflow files (GitHub blocks auto-commits to .github/workflows/)
  settings.global.excludes = [
    ".github/workflows/*"
  ];
}
