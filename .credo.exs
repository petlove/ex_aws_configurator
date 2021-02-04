%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "test/", "web/", "apps/", "live/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/", ~r"/test/support/factories/"]
      },
      strict: true,
      color: true,
      checks: [
        {Credo.Check.Warning.ApplicationConfigInModuleAttribute, false},
        {Credo.Check.Readability.ModuleDoc, false},
        {Credo.Check.Refactor.MapInto, false},
        {Credo.Check.Warning.LazyLogging, false},
        {Credo.Check.Design.TagTODO, false}
      ]
    }
  ]
}
