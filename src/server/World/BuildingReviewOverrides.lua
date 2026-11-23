-- County OBJECTID keyed, photograph-reviewed corrections. Missing fields stay
-- unknown. Local source images are private references, not distributed assets.
local G = "25_GoogleStreetView_Buildings/images/"
return {
 -- User's 2026-11-22 live Google visual review. These are type-only
 -- corrections; roof, entrance and materials are NOT inferred from a
 -- camera viewpoint that has not yet been surveyed for parcel identity.
 -- Old photo/GIS classifications remain traceable in PropertyReconstruction.
 ["33881"]={style="rowhouse",arch="flat_row",use="residential",manualPriority=true,
   confidence="user_visual_type_provisional",evidence="chester_google_visual_classifications.csv; 2026-11-22"},
 ["161384"]={style="rowhouse",arch="flat_row",use="residential",manualPriority=true,
   confidence="user_visual_type_provisional",evidence="chester_google_visual_classifications.csv; 2026-11-22"},
 ["84792"]={style="rowhouse",arch="flat_row",use="residential",manualPriority=true,
   confidence="user_visual_type_provisional",evidence="chester_google_visual_classifications.csv; 2026-11-22"},
 ["128777"]={style="rowhouse",arch="flat_row",use="residential",manualPriority=true,
   confidence="user_visual_type_provisional",evidence="user review: corner rowhome with left alley; no invented door bearing"},
 ["171786"]={style="rowhouse",arch="flat_row",use="residential",manualPriority=true,
   confidence="user_visual_type_provisional",evidence="user review: Butler Street rowhome side; orientation unresolved"},
 ["13452"]={style="garage",confidence="verified_type",evidence="2026-11-21 citywide full-size review"},
 ["147448"]={style="storefront",wall=0xddd0bf,material="Brick",name=false,sb=false,forceShop=true,photoFacade="777",roof="gable",manualPriority=true,
   -- Camera on Lincoln, heading 282, ray-cast centred on this polygon's
   -- Lincoln wall: the yellow 777 fascia and poster-glazed shop windows run
   -- along Lincoln (tile fb2=64 keeps that face glazed), the customer door is
   -- at the W 9th corner. The opaque graffiti wall is the west/rear side.
   shops={[0]={front=64,corner=154,entrance=154,entranceOffset=-0.57,canopy=false,photoFacade="777",
     signBg=0x183b88,signFg=0xf2ebcf}},confidence="high",
   evidence=G.."147448/front_7zG-idlY0xSp7aFu6woIUw.jpg; county 900 W 9th footprint"},
 ["93584"]={style="commercial",wall=0xe8e6e0,material="Brick",shopCanopy=false,
   surveyFront=65,surveyCorner=false,
   confidence="high_structure_medium_units",evidence=G.."93584/front_mekg61gwAx6XAn-CWPos4g.jpg; DVRPC 2025 aerial"},
 ["97558"]={style="garage",use="mixed_use_garages_housing",garageBays=3,wall=0xa64d44,material="Brick",confidence="high",evidence=G.."97558/front_4P-PoquEuqkifZJF-mbesw.jpg"},
 ["68468"]={style="twin",arch="colonial_twin",porch=true,wall=0x9f684e,material="Brick",confidence="high",evidence=G.."68468/front_TZcO1bSLzGewC3HqbS4e5w.jpg"},
 ["4639"]={style="twin",arch="colonial_twin",porch=true,wall=0x9b654c,material="Brick",confidence="high",evidence=G.."4639/front_iCJfsWvBdgVVrf1n_jKBMw.jpg"},
 ["17385"]={style="twin",arch="colonial_twin",porch=true,wall=0xa06950,material="Brick",confidence="high",evidence=G.."17385/front_xjxQbUrN-zkIXB7TnSERqw.jpg"},
 ["52062"]={style="twin",arch="colonial_twin",porch=false,wall=0xa46c53,material="Brick",confidence="medium",evidence=G.."52062/front_EV-sPB6WyDkRu0eoAFVg1A.jpg"},
 ["58981"]={style="twin",arch="colonial_twin",porch=false,wall=0xa26450,material="Brick",confidence="high",evidence=G.."58981/front_MAfKtdGSZ_bsMcXQEeMK8w.jpg"},
 ["184587"]={style="twin",arch="colonial_twin",porch=true,wall=0xa8745c,material="Brick",confidence="high",evidence=G.."184587/front_ogOe0Q4X7eg8X17fw_l-BA.jpg"},
 ["37959"]={style="rowhouse",arch="porch_row",porch=true,wall=0x9a5848,material="Brick",confidence="high",evidence=G.."37959/front_vG9rtZqhvhtesbdQ-7Tj3Q.jpg"},
 ["34237"]={style="rowhouse",arch="porch_row",porch=true,wall=0xa26050,material="Brick",confidence="high",evidence=G.."34237/front_h4Mx4O6AnJVg4TtgQXtMEg.jpg"},
 ["113017"]={style="rowhouse",arch="porch_row",porch=true,wall=0xa76251,material="Brick",confidence="high",evidence=G.."113017/front_h4Mx4O6AnJVg4TtgQXtMEg.jpg"},
 ["39766"]={style="rowhouse",arch="porch_row",porch=true,wall=0x9b5e4d,material="Brick",confidence="high",evidence=G.."39766/front_ZVZ86Fd3bgq4XJxXtyvlZg.jpg"},
 ["181213"]={style="rowhouse",arch="porch_row",porch=true,wall=0x975b47,material="Brick",confidence="high",evidence=G.."181213/front_UhMFjU5M27kiVmEprzbc2A.jpg"},
 ["139660"]={style="rowhouse",arch="flat_row",porch=false,wall=0x9c6656,material="Brick",confidence="medium",evidence=G.."139660/front_g_zE0RnERTDfxNICbh_2lQ.jpg"},
 ["79594"]={style="rowhouse",arch="flat_row",porch=false,wall=0x985745,material="Brick",confidence="medium",evidence=G.."79594/front_XORkHVSwecsSusdEKR8XzA.jpg"},
 ["82547"]={style="house",arch="victorian_house",porch=true,wall=0xe2dfd2,material="WoodPlanks",confidence="medium",evidence=G.."82547/front_iazm9NH0xAjKH8L5KMVRYw.jpg"},
 ["183747"]={style="twin",arch="victorian_twin",porch=true,bay=true,wall=0x9b6451,material="Brick",confidence="medium",evidence=G.."183747/front_KjxkYHyAtkf2CzRh03sLNQ.jpg"},
 ["99994"]={style="house",arch="colonial_house",porch=true,wall=0xe2ded3,material="WoodPlanks",confidence="high",evidence=G.."99994/front_xJvP_q8ej6ibyUOFn-T6CA.jpg"},
 ["94400"]={style="house",arch="victorian_house",porch=true,bay=true,wall=0xe4ded2,material="WoodPlanks",confidence="medium",evidence=G.."94400/front_R4b0LA3VqFoJUGpX-ix-LA.jpg"},
 ["81089"]={style="house",arch="colonial_house",porch=false,wall=0xa05c4b,material="Brick",confidence="medium",evidence=G.."81089/front_Wzf0EA0fl_-hslYSGWnc4A.jpg"},
 -- Further west and east blocks: each reference was read with its camera
 -- position against the 2025 aerial and adjacent county footprints.
 ["23871"]={style="garage",wall=0xb0b1ac,material="Brick",confidence="medium",evidence=G.."23871/front_cwJpDv8XQJlJ7ociTsIj8g.jpg"},
 ["95043"]={style="apartment",arch="apartment",wall=0xa16353,material="Brick",confidence="medium",evidence=G.."95043/front_nsAIrCGi7ZWdqfx3hTJbbg.jpg"},
 ["153497"]={style="rowhouse",arch="porch_row",porch=true,wall=0x9f6751,material="Brick",confidence="medium",evidence=G.."153497/front_c3M8FAy9aR7oT4nyURfSlw.jpg"},
 ["150015"]={style="twin",arch="victorian_twin",porch=true,wall=0xc4bdad,material="Brick",confidence="medium",evidence=G.."150015/front_IwGtx2h8z8zR_7D87qyCdg.jpg"},
 ["164928"]={style="house",arch="colonial_house",porch=false,wall=0xe1e1dc,material="WoodPlanks",confidence="medium",evidence=G.."164928/front_IwGtx2h8z8zR_7D87qyCdg.jpg"},
 ["162137"]={style="twin",arch="victorian_twin",porch=true,wall=0x9d654f,material="Brick",confidence="medium",evidence=G.."162137/front_Z1XyL8J9SGQOMNlRfS70Kw.jpg"},
 ["7613"]={style="twin",arch="colonial_twin",porch=true,wall=0xb7a798,material="Brick",confidence="medium",evidence=G.."7613/front_PYL17Y4J4YdXPP7LiIIShg.jpg"},
 ["5723"]={style="rowhouse",arch="flat_row",porch=false,wall=0x9d594a,material="Brick",confidence="medium",evidence=G.."5723/front_ixjklcOr_36MBDiLqNODrQ.jpg"},
 ["138612"]={style="house",arch="colonial_house",porch=true,wall=0xa56752,material="Brick",confidence="medium",evidence=G.."138612/front_zkX3PVOQJwEHfLF9bBLCeA.jpg"},
 ["64004"]={style="twin",arch="colonial_twin",porch=false,wall=0xc9c8c1,material="WoodPlanks",confidence="medium",evidence=G.."64004/front_hANPWwtjz8nEurDsKIGAXw.jpg"},
 ["28482"]={style="commercial",wall=0x9b624f,material="Brick",confidence="medium",evidence=G.."28482/front_6QQUYGJ3kEcXkPwDRotfRA.jpg"},
 ["178372"]={style="twin",arch="colonial_twin",porch=false,wall=0xe7e5df,material="WoodPlanks",confidence="medium",evidence=G.."178372/front_FCz6MelY3f1QmrRLr_owMA.jpg"},
 ["182911"]={style="twin",arch="colonial_twin",porch=false,wall=0xa47761,material="Brick",confidence="medium",evidence=G.."182911/front_4KGv8fExb6V4PCDoCocIew.jpg"},
 ["121174"]={style="twin",arch="colonial_twin",porch=true,wall=0xe0ddcf,material="WoodPlanks",confidence="medium",evidence=G.."121174/front_Q2s_V3_wFsgX2Up0SOH-NQ.jpg"},
 ["142656"]={style="twin",arch="colonial_twin",porch=true,wall=0xe2dfd2,material="WoodPlanks",confidence="medium",evidence=G.."142656/front_gvwq1FsvFoMYlt9bAICsRg.jpg"},
 ["564"]={style="house",arch="victorian_house",porch=true,bay=true,wall=0x9e6450,material="Brick",confidence="medium",evidence=G.."564/front_hDIgeqfGu6AUJwPHvE0atw.jpg"},
 ["44085"]={style="garage",wall=0x855b4e,material="Brick",confidence="medium",evidence=G.."44085/front_PAFNzwxTo10RXRTk26WYqA.jpg"},
 ["25111"]={style="school",use="education",roof="gable",wall=0x777774,material="Cobblestone",
   confidence="high",evidence=G.."25111/front_CHHY-R-CVqOHneA5elpMhQ.jpg; county 733 W 9th footprint"},
 ["82905"]={style="church",use="religious",gothic=true,wall=0xa59983,material="Cobblestone",
   confidence="high",evidence=G.."82905/front_9YUPzXIbZkcGxZHk5X9CcA.jpg"},
 ["20046"]={style="church",use="religious",wall=0xa96c55,material="Brick",
   confidence="medium",evidence=G.."20046/front_xOR3BKjM9hb7znEWEsTsZA.jpg"},
 ["17618"]={style="church",use="religious",wall=0xe4e3dc,material="SmoothPlastic",
   confidence="medium",evidence=G.."17618/front_X51leE7-kVlny4tWq7GIGw.jpg"},
}
