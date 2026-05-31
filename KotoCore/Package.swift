// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "KotoCore",
  platforms: [.macOS(.v13)],
  products: [
    // No explicit type = automatic (resolves to static). Do NOT make it dynamic:
    // a dynamic framework breaks bundling of the converter's default dictionary resource into the app.
    .library(name: "KotoCore", targets: ["KotoCore"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
      revision: "ea4093aa99f4c8a4d5b0918a7dcae6346c8da142"
    )
  ],
  targets: [
    .target(
      name: "KotoCore",
      dependencies: [
        .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
        .product(
          name: "KanaKanjiConverterModuleWithDefaultDictionary",
          package: "AzooKeyKanaKanjiConverter"
        ),
      ]
    )
  ]
)
