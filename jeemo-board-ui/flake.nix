{
  description = "Jeemo board — QML frontend for the jeemo_net core module";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Placeholder — override with the sibling source at build time:
    #   nix build --override-input jeemo_net path:../jeemo-core '.#lgx-portable'
    jeemo_net.url = "github:logos-co/logos-module-builder";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
