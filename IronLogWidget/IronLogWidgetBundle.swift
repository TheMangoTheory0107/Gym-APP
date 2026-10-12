import SwiftUI
import WidgetKit

@main
struct IronLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        RestLiveActivity()
    }
}
