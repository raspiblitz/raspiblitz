# Community development
Everybody is welcome to join, improve, and extend the RaspiBlitz - it's a work in progress. Check the issues if you wanna help out or add new ideas. You can find the scripts used for RaspiBlitz interactions on the device at /home/admin or in this Git repo's subfolder home.admin.

## Understanding Blitz project
RaspiBlitz is insipired by the [RaspiBolt guide](https://raspibolt.github.io/raspibolt/). Tutorial on how to build a lightning node on the RaspberryPi. So much thx to Stadicus :)
To start your Deep Dive into the RaspiBlitz project, watch [this video](https://www.youtube.com/watch?v=QXUGg45CWLo).

### Blitz philosophy

* DIY community development, if you are unhappy with the code, fork and pull request, this will make you you DYOR instead of depending on the developers.
* If you ask when the next release will be available, we don't know, but if you contribute, it might be faster.
* Be sure to contribute back, every little help is wanted.

## Getting started
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
1. **Config script** --> Integrate your executable into the RaspiBlitz enviroment.
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
1. Open a pull request (PR are made to the `dev` branch unless indicated otherwise by a collaborator.

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
1. Code that breaks the enviroment.
1. Enhancing current services functionality.
1. Solving a common issue.
1. Adding new applications.

Project maintainers reserve the right to weigh the opinions of peer reviewers using common sense judgement and may also weigh based on merit.
Reviewers that have demonstrated a deeper commitment and understanding of the project over time or who have clear domain expertise may naturally have more weight, as one would expect in all walks of life.

## Release policy
The project leader is the release manager for each RaspiBlitz release.

## Copyright
By contributing to this repository, you agree to license your work under the [MIT license](https://github.com/rootzoll/raspiblitz/blob/master/LICENSE).
Any work contributed where you are not the original author must contain its license header with the original author(s) and source.
