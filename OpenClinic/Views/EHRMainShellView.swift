import SwiftUI
import SwiftData
import os

struct EHRMainShellView: View {
    @State private var activeTab: TabSelection = .patient

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    enum TabSelection {
        case agenda, patient, intelligence, inbox, settings
    }

    init() {
        #if os(iOS)
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.35)
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }

    var body: some View {
        TabView(selection: $activeTab) {
            AgendaView()
                .tabItem {
                    Label("Agenda", systemImage: "calendar")
                }
                .tag(TabSelection.agenda)
                .onAppear { AppLogger.nav.info("📅 Agenda tab appeared") }

            // On iPad, show the split-view dashboard; on iPhone, show the simpler list
            Group {
                #if os(iOS)
                if horizontalSizeClass == .regular {
                    iPadClinicalDashboard()
                } else {
                    PatientDashboardView()
                }
                #else
                iPadClinicalDashboard()
                #endif
            }
            .tabItem {
                Label("Patient", systemImage: "person.crop.circle")
            }
            .tag(TabSelection.patient)
            .onAppear { AppLogger.nav.info("🧑‍⚕️ Patient tab appeared") }

            ClinicIntelligenceView()
                .tabItem {
                    Label("Intelligence", systemImage: "brain.head.profile")
                }
                .tag(TabSelection.intelligence)
                .onAppear { AppLogger.nav.info("🧠 Intelligence tab appeared") }

            InboxView()
                .tabItem {
                    Label("IntraMail", systemImage: "envelope")
                }
                .tag(TabSelection.inbox)
                .onAppear { AppLogger.nav.info("📬 Inbox tab appeared") }

            OpenClinicSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(TabSelection.settings)
                .onAppear { AppLogger.nav.info("⚙️ Settings tab appeared") }
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .tint(.clinicalIndigo)
    }
}
