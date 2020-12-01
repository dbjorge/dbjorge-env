# dbjorge-env

Environment configuration for my home/work machine(s) (mostly Windows)

## Tools I install on a new machine (in no particular order)

- [Windows Terminal](https://www.microsoft.com/en-us/p/windows-terminal/9n0dx20hk701)
- [PowerShell](https://github.com/powershell/powershell)
  - [posh-git](https://github.com/dahlbyk/posh-git) (`Install-Module posh-git`)
- [Git](https://git-scm.com/download/win)
- [gh (GitHub CLI)](https://github.com/cli/cli)
- [Rust](https://www.rust-lang.org/learn/get-started), for installing:
  - [ripgrep](https://github.com/BurntSushi/ripgrep) (`cargo install ripgrep`)
  - [bat](https://github.com/sharkdp/bat) (`cargo install bat`)
- [nvm-windows](https://github.com/coreybutler/nvm-windows) to install Node
  - [yarn](https://yarnpkg.com/) (use NVM to install Node.js LTS, then `npm install -g yarn`)
- [VS Code](https://code.visualstudio.com/docs/setup/windows), with notable extensions:
  - Bracket Pair Colorizer 2
  - GitLens
  - ESLint
  - Live Share
  - Prettier
  - XML Tools
- [IntelliJ Idea Community](https://www.jetbrains.com/idea/download/) if I'm doing Java development (eg, [jorbs-spire-mod](https://github.com/dbjorge/jorbs-spire-mod))
- [Android Studio](https://developer.android.com/studio) if I'm doing Android development (eg, [accessibility-insights-for-android-service](https://github.com/microsoft/accessibility-insights-for-android-service))
- [Beyond Compare](http://www.scootersoftware.com/download.php)

## Usage

After installing tools, I clone this repo (usually to `D:\repos\dbjorge-env`, whichever drive is the fastest SSD), then run `Install.ps1`, which registers redirects for Git and PowerShell to essentially symlink them to this repo's `Profile.ps1` and `gitconfig_global.txt`.
