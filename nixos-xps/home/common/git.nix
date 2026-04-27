{...}: {
  programs.git = {
    enable = true;
    # Set your details here or override with `git config --global`
    userName  = "Your Name";
    userEmail = "your@email.com";
    signing.key = null; # set to your GPG key fingerprint if desired

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      core.editor = "nvim";
      core.autocrlf = "input";
      diff.colorMoved = "default";
      merge.conflictstyle = "diff3";
    };

    delta = {
      enable = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
        syntax-theme = "Catppuccin Mocha";
      };
    };

    aliases = {
      st  = "status";
      co  = "checkout";
      br  = "branch";
      lg  = "log --oneline --graph --decorate --all";
      undo = "reset HEAD~1 --mixed";
      wip = "!git add -A && git commit -m 'WIP'";
    };
  };

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };
}
