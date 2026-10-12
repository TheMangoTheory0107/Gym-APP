import CoreText
import Foundation

/// Registers every bundled .ttf/.otf at launch, so no Info.plist font list is needed.
enum FontRegistrar {
    static func registerAll() {
        let urls = ["ttf", "otf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
