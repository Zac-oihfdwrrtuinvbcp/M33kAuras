# Contributing to M33kAuras

## Code Standards

There are a few things which we require in any contribution:

- This repository comes with a `.editorconfig` file, so the following requirements will be taken care of if you have [EditorConfig](https://editorconfig.org/) installed:
  - Tabs consist of 2 spaces.
  - Files end with a newline.
  - No trailing whitespace at the end of a line.
- All user-facing strings (`names` and `desc` fields in AceConfig tables, mostly) must be localized:
  - We use a locale scraper to find translation phrases and automatically export them to CurseForge for translation. This scraper parses the addon files, looking for tokens that look like: `L["some translation phrase"]`. You must use double quoted strings, and name the localization table (found at `M33kAuras.L`) `L` in your code for this to work properly.
- When writing a new file, avoid using semicolons. When modifying code in an existing file, try to be consistent, but err on the side of no semicolons.
- New features should be indicated by concatenating `M33kAuras.newFeatureString` onto the associated translation phrase. We will remove the new feature indicator approximately 3 months after the first release.

## Secret-value help text

Use the same gold **Secret values** heading for trigger descriptions and option
tooltips: `"|cffffd200" .. L["Secret values"] .. "|r"`. Keep the body in the normal
text color. For prototype descriptions, put the heading in `display` and the
body in `text`; do not put a whole paragraph in the large heading. Use medium
font size for the description body so it is readable below the large heading.

Write short, user-facing sentences in this order:

1. Explain when the relevant information becomes secret, if the rule is known.
2. Explain the effect on this trigger or filter.
3. Explain what can still be shown or which option the user can change.

In trigger overviews, separate the circumstances from the effect and next step
with a blank line. Name the option users can change, such as "Choose Always"
or "Leave this filter unchecked." Prefer "check whether the spell is ready"
over "determine readiness" and "checks of a unit's target" over "inherited
identity restrictions." Keep field tooltips focused on that field instead of
repeating the full overview. Preserve distinctions between information that can
be displayed, information that can be checked, and displays that stop updating.

Show the overall explanation once per trigger. Put field-specific details in
the affected option's tooltip, after its existing help text with a blank line.
Use consistent wording such as "When this value is secret, this filter cannot
match." Only promise that behavior when the implementation actually rejects
the filter; missing values, skipped updates, and estimated readiness require
their own explanations. Do not imply that a hidden aura is necessarily absent.

For spell cooldown triggers, use "When cooldown is secret" consistently for
timing, charges, and spell counts. Do not describe these as separate secrecy
rules; explain the effect on the selected option after that shared wording.
Similarly, use "When the cast is secret" for cast names, spell IDs, interruptibility,
remaining time, and empowered stages, and "When power is secret" for resource
amounts, percentages, and deficits. Use "When totem information is secret" for
totems. Retain separate wording where the rules actually differ: maximum power,
threat status versus threat values, and unit identity versus cast information.
For character stats, keep "When this stat is secret or unavailable" because each
filter must still work when its own stat is available.

Check `Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua` in
the WoW UI source and the predicates on the actual API used by the trigger.
Predicate names and API names belong in developer documentation, not in the
tooltips. Relevant distinctions include:

- Aura, cooldown, and totem rules can depend on combat, encounter, challenge-mode,
  or PvP restrictions, with always/never-secret spell exceptions taking priority.
- Cast rules normally exempt the player and their pet, with spell exceptions.
  Do not describe all cast secrecy as combat-only or promise that own casts are
  always public.
- Power amounts depend on resource type; maximum power also depends on whether
  the unit is player-controlled.
- Threat status and detailed threat values have different unit-based rules.
  Check which API the trigger uses before promising that a field is available.
- Identity and unit-comparison rules differ. Names have an additional PvP
  exception; compound unit tokens can inherit restrictions. A unit comparison
  can be unsupported independently of whether its result would be secret.
- The stat predicate does not specify a precise list of circumstances. Do not
  invent one or equate all secrecy with the global restriction flag.

These are conditional rules, not a promise about the value currently returned.
Preserve qualifiers such as "normally" and "generally" where the documentation
uses them. Localize complete sentences with `L["..."]`.

## Pull Requests

If you want to help, here's what you need to do:

1. Make sure you have a [GitHub account](https://github.com/signup/free).
1. [Fork](https://github.com/m33shoq/M33kAuras/fork) our repository.

1. Create a new topic branch (based on the `main` branch) to contain your feature, change, or fix.

    ```bash
    git checkout -b my-topic-branch
    ```

1. Set `core.autocrlf` to true.

    ```bash
    git config core.autocrlf true
    ```

1. Set `pull.rebase`to true.

    ```bash
    git config pull.rebase true
    ```

1. Set up your [Git identity](https://git-scm.com/book/en/v2/Getting-Started-First-Time-Git-Setup) so your commits are attributed to your name and email address properly.

1. Take a look at our [Wiki](https://github.com/m33shoq/M33kAuras/wiki/Lua-Dev-Environment) page on how to setup a Lua dev environment.

1. Install an [EditorConfig](https://editorconfig.org/) plugin for your text editor to automatically follow our indenting rules.

1. Commit and push your changes to your new branch.

    ```bash
    git commit -a -m "commit-description"
    git push
    ```

1. [Open a Pull Request](https://github.com/m33shoq/M33kAuras/pulls) with a clear title and description.

### Keeping your fork updated

- Specify a new remote upstream repository that will be used to sync your fork (you only need to do this once).

  ```bash
  git remote add upstream https://github.com/m33shoq/M33kAuras.git
  ```

- In order to sync your fork with the upstream M33kAuras repository you would do

  ```bash
  git fetch upstream
  git checkout main
  git rebase upstream/main
  ```

- You are now all synced up.

### Keeping your pull request updated

- In order to sync your pull request with the upstream M33kAuras repository in case there are any conflicts you would do

  ```bash
  git fetch upstream
  git checkout my-topic-branch
  git rebase upstream/main
  ```

- In case there are any conflicts, you will now have to [fix them manually](https://help.github.com/articles/resolving-merge-conflicts-after-a-git-rebase/).
- After you're done with that, you are ready to force-push your changes.

  ```bash
  git push --force
  ```

- Note: Force-pushing is a destructive operation, so make sure you don't lose something in the progress.
- If you want to know more about force-pushing and why we do it, there are a two good posts about it: one by [Atlassian](https://www.atlassian.com/git/tutorials/merging-vs-rebasing#the-golden-rule-of-rebasing) and one on [Reddit](https://www.reddit.com/r/git/comments/6jzogp/why_am_i_force_pushing_after_a_rebase/).
- Your pull request should now have no conflicts and be ready for review and merging.

## Reporting Issues and Requesting Features

1. Please check our [issue tracker](https://github.com/m33shoq/M33kAuras/issues) for your problem since there's a good
   chance that someone has already reported it.
1. If you find a match, please try to provide as much info as you can,
   so that we have a better picture about what the real problem is and how to fix it ASAP.
1. If you didn't find any tickets with a problem similar to yours then please open a
   [new ticket](https://github.com/m33shoq/M33kAuras/issues/new/choose).
    - Be descriptive as much as you can.
    - Provide everything the template text asks you for.
