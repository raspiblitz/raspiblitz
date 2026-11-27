# Community development

Everybody is welcome to join, improve, and extend the RaspiBlitz - it's a work in progress. Check the issues if you wanna help out or add new ideas. You can find the scripts used for RaspiBlitz interactions on the device at /home/admin or in this Git repo's subfolder home.admin.

## Understanding Blitz project

RaspiBlitz is inspired by the [RaspiBolt guide](https://raspibolt.github.io/raspibolt/). Tutorial on how to build a lightning node on the RaspberryPi. So much thx to Stadicus :)
To start your Deep Dive into the RaspiBlitz project, watch [this video](https://www.youtube.com/watch?v=QXUGg45CWLo).

### Blitz philosophy

* DIY community development, if you are unhappy with the code, fork and pull request, this will make you DYOR instead of depending on the developers.
* If you ask when the next release will be available, we don't know, but if you contribute, it might be faster.
* Be sure to contribute back, every little help is wanted.

## Getting started

### Build v1.12 manually on a Raspberry Pi or Debian VM

Use fresh Raspberry Pi OS Bookworm 64-bit on a separate Pi boot medium, or install Debian 12 amd64 inside a fresh guest VM. The builder changes users, packages and system services on the machine where it runs. Use an isolated network during provisioning because the image starts with known setup passwords. Keep existing node data disks detached during the build.

1. Check the vendor checksum/signature for the base image. The [Pi build definition](ci/arm64-rpi/) records the base used by the project. Boot the base OS, enable wired networking, and make sure the build account can use sudo.
2. Install Git if needed. Clone the release branch into the build user's home, away from the installer's destination `/home/admin/raspiblitz`. Record the source commit before starting.

   ```bash
   git clone --branch v1.12 --single-branch https://github.com/raspiblitz/raspiblitz.git ~/raspiblitz-build
   cd ~/raspiblitz-build
   git rev-parse HEAD
   ```

3. For a minimal Pi image run `sudo bash build_sdcard.sh -b v1.12 -f 0 -d headless`. On a Debian VM use `sudo bash build_sdcard.sh -b v1.12 -f 0 -d headless -t 0 -w off`. Use `-f 1` to build Fatpack. Check the interactive summary and review the output through the final display step.
4. Compare `git -C /home/admin/raspiblitz rev-parse HEAD` as the admin user with the recorded commit. The installer fetches the named branch again. If it moved, reconcile the two revisions before using the build for a release.
5. To use the new machine, reboot, then log in as `admin` and complete first setup. If you deliberately paused provisioning, clear your stop marker from `/boot/firmware/stop` or `/home/admin/stop` and detach any virtual audio device used as a stop signal. To distribute an image instead, review the extra login accounts, start a fresh admin shell and run `release`. Capture the powered-off system disk, checksum the image, and boot a separate copy to check the first login. Booting that copy generates its own host keys.

Get all details on "How to contribute to RaspiBlitz Development" on [this video](https://www.youtube.com/watch?v=ZVtZepV3OfM).

### Levels

All levels are important. Even advanced users help on basic levels for other Blitzers. Every help is welcome.
Not all enhancements needs to go through all levels, these are levels of difficulty, scalability depends on your skills.

#### Basic

1. **Reporting user side** --> Open an issue to indicate a problem or make a feature request.
1. **Community support** --> Solve other people issues.
1. **Good first issue** --> The purpose of the good first issue label is to highlight which issues are suitable for a new contributor without a deep understanding of the codebase.

#### Medium

1. **Sovereignty** --> Fork the repo to have the changes controlled by you.
1. **Experiment** --> Try things out on your RaspiBlitz.
1. **Executable** --> Turn your experiment into a basic shell script.

#### Advanced

1. **Config script** --> Integrate your executable into the RaspiBlitz environment.
1. **SSH-GUI** --> Make it easier for others to use your config script.
1. **WEB-GUI** --> Turn your feature into customer ready

### Workflow

Use the `github` command from terminal to set your RaspiBlitz to your own forked repo and development branch and use the command `patch` to sync your RaspiBlitz quickly with your latest commits. 

**Solving issues**

You do not need to request permission to start working on an issue. However,
you are encouraged to leave a comment if you are planning to work on it. This
will help other contributors monitor which issues are actively being addressed
and is also an effective way to request assistance if and when you need it.

#### Pull Request

1. Make sure it is compatible with Blitz philosophy.
1. Fork the repo
1. Commit changes on the new branch
1. Open a pull request (PRs are made to the `dev` branch unless indicated otherwise by a collaborator.

#### Review

##### Conceptual review

A review can be a conceptual review, where the reviewer leaves a comment

* Concept (N)ACK, meaning "I do (not) agree with the general goal of this pull
request",
* Approach (N)ACK, meaning Concept ACK, but "I do (not) agree with the
approach of this change".

A NACK needs to include a rationale why the change is not worthwhile.
NACKs without accompanying reasoning may be disregarded.

##### Code review 

After conceptual agreement on the change, code review can be provided. A review begins with the urgent necessity of the changes.
Start from urgent to less important:
1. Security risk.
1. Code that breaks the environment.
1. Enhancing current services functionality.
1. Solving a common issue.
1. Adding new applications.

Project maintainers reserve the right to weigh the opinions of peer reviewers using common sense judgement and may also weigh based on merit.
Reviewers that have demonstrated a deeper commitment and understanding of the project over time or who have clear domain expertise may naturally have more weight, as one would expect in all walks of life.

## Release policy
The project leader is the release manager for each RaspiBlitz release.

## Copyright
By contributing to this repository, you agree to license your work under the [MIT license](https://github.com/raspiblitz/raspiblitz/blob/master/LICENSE).
Any work contributed where you are not the original author must contain its license header with the original author(s) and source.
