# dbjorge-env

Environment configuration for my home/work machine(s) (mostly Windows)

## Tools I install on a new machine (in no particular order)

- [FiraMono Nerd Font](https://www.nerdfonts.com/font-downloads) (find your favorite at [programmingfonts.org](https://www.programmingfonts.org/))
- [Git](https://git-scm.com/download/win)
- [gh (GitHub CLI)](https://github.com/cli/cli)
- [Rust](https://www.rust-lang.org/learn/get-started), for installing:
  - [ripgrep](https://github.com/BurntSushi/ripgrep) (`cargo install ripgrep`)
  - [bat](https://github.com/sharkdp/bat) (`cargo install bat`)
- [nvm](https://github.com/nvm-sh/nvm)
  - [yarn](https://yarnpkg.com/) (use NVM to install Node.js LTS, then `npm install -g yarn`)
- [Cursor](https://cursor.com/), with notable extensions:
- [IntelliJ Idea Community](https://www.jetbrains.com/idea/download/) if I'm doing Java development (eg, [jorbs-spire-mod](https://github.com/dbjorge/jorbs-spire-mod))
- [Android Studio](https://developer.android.com/studio) if I'm doing Android development (eg, [accessibility-insights-for-android-service](https://github.com/microsoft/accessibility-insights-for-android-service))
- [Beyond Compare](http://www.scootersoftware.com/download.php)
- [zsh](https://en.wikipedia.org/wiki/Z_shell)
  - [zsh-completions](https://github.com/zsh-users/zsh-completions) ([OBS repo](https://software.opensuse.org/download.html?project=shells%3Azsh-users%3Azsh-completions&package=zsh-completions))
  - [zsh-history-substring-search](https://github.com/zsh-users/zsh-history-substring-search) (`gh repo clone zsh-users/zsh-history-substring-search`)
  - [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) ([OBS repo](https://software.opensuse.org/download.html?project=shells%3Azsh-users%3Azsh-syntax-highlighting&package=zsh-syntax-highlighting))

### Mac

- [Rectangle Pro](https://rectangleapp.com/pro)

### Windows

- [nvm-windows](https://github.com/coreybutler/nvm-windows)
- [Windows Terminal](https://www.microsoft.com/en-us/p/windows-terminal/9n0dx20hk701)
- [PowerShell](https://github.com/powershell/powershell)
  - [oh-my-posh](https://ohmyposh.dev/) (`winget install JanDeDobbeleer.OhMyPosh`)
  - [posh-git](https://github.com/dahlbyk/posh-git) (`Install-Module posh-git`)

Use `Install.ps1` for initial setup.

## Setup

1. Install tools above
2. Set up a repos folder
  - On Mac/Linux, `~/repos`
  - On Windows `C:\repos`
3. From repos dir, `gh clone dbjorge/dbjorge-env`
4. `install-zsh.sh` / `Install.ps1`
