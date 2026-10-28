# Store release: what needs Remington's say-so (P439)

Written Oct 24 2026 for "In the next round of builds, I want it to be ready to be put on the store... anything that
needs my say so". The game's own store build is ready to make (`STORE=1 quest/tools/build-apk.sh`, then
`quest/tools/storecheck.sh` on the APK: release signing, ARM64 only, no microphone, no forbidden permissions, VR
intent; see meta-checks.md). What is left is in this list: things only you can do or decide. Nothing here was done for
you.

## His answers (Oct 27 21:12, P479)
- Early Access, US$9.99 (set by the overseer on the dashboard; nothing in the build). App ID 1396130500248132 under
  Noobmaster Industries; the release key is on his Mac, never in the repo.
- Gambling: cut. The saloon dice, poker and knife game are gone from every build.
- The Director's language model: gone, and the cloud planner with it; the rules plan every event.
- Co-op: scrapped for now (Play Together and split screen).
- Credits: "A game by Remington Wilbur, Noobmaster Industries", made with Claude by Anthropic.
- AI content: yes. "AI didn't just influence the creation of this game. No, it made it."

## Accounts and keys (only you can do these)
1. **Meta Horizon developer account and the app's store page.** Create the app in the Meta Horizon Developer Dashboard
   (organisation, payment and tax details). It gives the **app ID**: build the store APK with `QUEST_APP_ID=<id>` so the
   ownership (entitlement) check works.
2. **Release signing key.** Make one keystore and keep it safe for the life of the game (a lost key means you can never
   update the store app). Build with `STORE_KEYSTORE`, `STORE_KEY_ALIAS`, `STORE_KS_PASS` set. Don't let it into the repo.
3. **Publisher name, contact email and date** in privacy-policy.md, and host that page at a public web address (the
   store asks for its link).

## Decisions
4. **Price**, and whether there's a demo or early access. (Answered: Early Access, US$9.99.)
5. **Age rating questionnaire (IARC).** Draft answers in iarc-answers.md. Expected result: 18+ / Mature, for war
   violence against human soldiers. Two answers are yours to confirm:
   - **Simulated gambling**: answered, cut (the saloon dice, poker and knife game are gone).
   - **Alcohol**: saloons and drink as set dressing. Keep as is.
6. **Rights to the generated assets** (credits-and-licences.md now lists where each comes from):
   - Music: 40 tracks you made in Google Flow Music. Confirm Flow's terms allow sale in a paid app.
   - Textures: generated with Google Gemini. Confirm commercial use under the account's terms.
   - Sound effects and townsfolk voices: ElevenLabs (the effects with a commercial licence; the voices through
     OpenRouter). Confirm the voices too.
   - The store's submission form asks whether the app uses AI-generated content: the answer is yes (art, sound, music,
     voices).
7. **The Director's language model**: answered, gone (the rules plan every event).
8. **Play Together**: answered, scrapped for now (Play Together, split screen and the Wi-Fi permissions are gone;
   the listing is single player and the rating answer is "users interact: no").
9. **Credits line**: answered: "A game by Remington Wilbur, Noobmaster Industries", made with Claude by Anthropic.
10. **Comfort rating**: proposed Moderate (comfort-rating.md). Flying craft and the frigate may push Meta to
    Intense; you can accept that or ask for comfort defaults to be tightened.

## On the headset (needs you, takes about an hour)
11. One 30-minute play session on the store build with no crash, then 5 minutes in a busy place checking that it
    holds 72 fps without the headset getting hot (Meta's tests).
12. Store art: capture the screenshots and the trailer clip in the game (art-plan.md lists the shots).

## Already handled in the build (no action)
- No microphone in the store build (the voice notes and the playtest tools are playtest builds only).
- Nothing leaves the headset but the bug and idea reports a player chooses to send (P480: words, a random report ID,
  version and place in the game); no telemetry, no online planner, no voice upload.
- No real insignia, parties, units, people or weapon names; every name is Sunderfall's own (docs/status/ip-renames.md).
- No profanity in townsfolk or soldier lines (the swear words in the code are block-lists, not lines).
- Pauses and saves when the headset comes off or the system menu opens.
