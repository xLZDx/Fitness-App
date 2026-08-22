import {
  assertRegisteredOfficialManufacturerSource,
  UnregisteredSourceError,
} from "../p1/adapters/registry_check";

describe("assertRegisteredOfficialManufacturerSource", () => {
  test("accepts a real, registered OFFICIAL_MANUFACTURER sourceId", () => {
    expect(() =>
      assertRegisteredOfficialManufacturerSource("technogym_product_catalog"),
    ).not.toThrow();
  });

  test.each([
    "technogym_product_catalog",
    "matrix_fitness_product_catalog",
    "life_fitness_hammer_strength_product_catalog",
    "core_health_fitness_nautilus_product_catalog",
  ])("accepts %s (the four real P1.G2 registry entries)", (sourceId) => {
    expect(() => assertRegisteredOfficialManufacturerSource(sourceId)).not.toThrow();
  });

  test("rejects a sourceId that is not registered at all", () => {
    expect(() => assertRegisteredOfficialManufacturerSource("totally_made_up_source")).toThrow(
      UnregisteredSourceError,
    );
  });

  test("rejects a real sourceId registered under a non-OFFICIAL_MANUFACTURER class (SEARCH_DISCOVERY)", () => {
    expect(() =>
      assertRegisteredOfficialManufacturerSource("search_engine_image_discovery"),
    ).toThrow(UnregisteredSourceError);
  });

  test("rejects a real sourceId registered under a non-OFFICIAL_MANUFACTURER class (MARKETPLACE_3D)", () => {
    expect(() => assertRegisteredOfficialManufacturerSource("sketchfab")).toThrow(
      UnregisteredSourceError,
    );
  });

  test("rejects a real sourceId registered under a non-OFFICIAL_MANUFACTURER class (WGER)", () => {
    expect(() => assertRegisteredOfficialManufacturerSource("wger_project")).toThrow(
      UnregisteredSourceError,
    );
  });
});
