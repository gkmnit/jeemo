{
  description = "Jeemo core — menus and ratings over logos-delivery";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    delivery_module.url = "github:logos-co/logos-delivery-module";

    # crates.io answers 403 to nixpkgs' older fetchCargoVendor, which breaks
    # the zerokit vendor step every delivery_module dependant builds through.
    # Redirect that one node to a nixpkgs that sends a User-Agent. Drop this
    # once logos-delivery advances its own pin past 2026-06-22.
    nixpkgs-vendor-fix.url = "github:NixOS/nixpkgs/2a0e0baec1c99cdc087c14f83ac6c31c929d14eb";
    delivery_module.inputs.logos-delivery.inputs.nixpkgs.follows = "nixpkgs-vendor-fix";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
