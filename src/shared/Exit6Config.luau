-- EXIT 6 gameplay configuration. Independent of ChesterWorld GIS.
return {
 StartingCash = 250,
 StartingReputation = 0,
 WalkSpeed = 16,
 SprintSpeed = 24,
 InteractionDistance = 12,
 DataStoreName = "Exit6PlayerData_v1",
 AutosaveSeconds = 120,
 -- stores run the shop system (Exit6Shop.server: cashier, menu, stock shift)
 -- instead of the starter one-button shift / drink prompts
 ShopSystem = true,
 -- Exit6Pedestrians.server: sidewalk walkers and store-front hangers-out in
 -- the real-buildings region (WorldConfig.REAL_BUILDINGS_REGION)
 Pedestrians = { walkers = 22, hangers = 8 },
}
