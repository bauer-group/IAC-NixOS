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

  # Exclude .github/ (auto-commits to workflows require special permissions)
  settings.global.excludes = [
    ".github/**"
  ];
}
