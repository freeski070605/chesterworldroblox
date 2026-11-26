# V3.1 character integration staging

Branch: `feature/exit6-character-v31` in the isolated worktree at `E:\code\chesterworld-character-v31`.
Approved appearance tag: `exit6-male-v3.1-approved`. Original V3 tag: `exit6-male-v3-approved`.
Neither tag includes the later character integration changes. The V3 source is byte-identical to its approval tag.

## Assets and test place

The upload bundle is `assets/wear/exit6_male_v31/`. It contains the corrected body, approved separate hair/face parts, and rebuilt briefs, cargo, puffer, sneakers and jewelry. The body GLB has 19 bone-parented attachment markers and the approved body mesh buffers are unchanged (`python tools/characters/verify_v31_body_lock.py`).

0. After any wear rebuild: `python tools/characters/sync_v31_wear_bbox.py --check` and `python tools/characters/verify_v31_body_lock.py` must pass.
1. In the separate `Exit6_CharacterTest.rbxl` place, upload the seven bundle GLBs and replace the old `ServerStorage` imports. Use the existing import names expected by `tools/character_test/install_exit6_v31.luau` and `install_exit6_v31_wear.luau`.
2. Run both installers, then rerun `install_exit6_v31.luau` to dress `StarterCharacter`.
3. Run `tools/character_test/verify_exit6_v31.luau`. Confirm all 15 WrapTargets, clothing layer orders, the two chain variants and R15 rig.
4. Play test walking, running, jumping, crouching, respawn, camera, phone, vehicles, Bike Life, basketball and Xbox input. Inspect briefs/cargo and sleeve seams during motion. Record frame rate and memory with one player and several nearby avatars.

The test uploads have not been made for this revision, so Play results are pending.

## Reversible integration

The new server script selects `ServerStorage.Exit6_V31_Character` as `StarterPlayer.StarterCharacter` only when the DataModel attribute `Exit6V31CharacterEnabled` is true. With the attribute false, the current character path remains active. Changing the switch affects subsequent spawns; respawn test players after changing it.

`Exit6Style` routes V3.1 characters through layered `Accessory` templates in `ServerStorage.Exit6_V31_Wear` and `Exit6_V31_Accessories`. Other R15 characters keep the current welded wear path. The existing profile, Chester Cash and reputation values remain the purchase and save authority. Premium purchases still pass through the entitlement receipt store, and that store rejects reputation-gated grants.

Cash entries currently staged: V3.1 twists, facial hair, puffer, cargos, sneakers, chain and watch. The puffer, cargos and sneakers also have Robux product entries; their product IDs are 0 until the owner configures developer products. Puffer and cargo color palettes save with outfits. With a compatible top the player chooses the chain over or under it (`chainlayer` verb, phone Closet, saved as `style.chainLayer` and per outfit); compatibility lives in `Exit6V31Style.ChainFit`, and an unlisted top hides the chain rather than clip it.

Skin-tone ColorMaps are generated in `assets/characters/exit6_male/textures_v3_1/skin_tones/`. For each uploaded map, add a `StringValue` under `ServerStorage.Exit6_V31_SkinToneMaps` named `1` through `10` with the matching `rbxassetid://...` value. The server refuses a skin-tone change on V3.1 until that map is installed.

## Release gates

Do not turn on the switch in the Exit 6 place, publish the place, or configure live Robux product IDs until the character test place passes and the user approves the integrated character. The current asset set does not yet include V3.1 fitted hoodies, shirts, jeans, shorts, boots, additional hairstyles, earrings or bracelets. Existing standard-R15 wardrobe items remain saved but are not a tested V3.1 fit.
