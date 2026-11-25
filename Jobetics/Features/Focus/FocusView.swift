import SwiftData
import SwiftUI

/// Pomodoro focus timer.
struct FocusView: View {
    @Environment(FocusTimer.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<BoardTask> { $0.statusRaw != "done" }, sort: \BoardTask.dueDate) private var tasks: [BoardTask]
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                phasePicker
                dial
                controls
                sessionsRow
                taskPicker
            }
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                (focus.phase.isBreak ? Color.teal : Brand.indigo).opacity(0.12).ignoresSafeArea()
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark", role: .close) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Settings", systemImage: "slider.horizontal.3") { showsSettings = true } }
            }
            .sheet(isPresented: $showsSettings) { FocusSettingsView() }
            .animation(.smooth, value: focus.phase)
        }
    }

    private var phasePicker: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(FocusPhase.allCases, id: \.self) { phase in
                    Button {
                        focus.reset()
                        focus.start(phase)
                        focus.pause()
                    } label: {
                        Text(phase.title).font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .selectableCapsule(focus.phase == phase)
                }
            }
        }
    }

    private var dial: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = focus.session.isIdle ? focus.settings.duration(of: focus.phase) : focus.session.remaining(at: context.date)
            let total = focus.settings.duration(of: focus.phase)
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: 1 - remaining / total)
                    .stroke(focus.phase.isBreak ? AnyShapeStyle(Color.teal.gradient) : AnyShapeStyle(Brand.angular),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                VStack(spacing: 6) {
                    Image(systemName: focus.phase.symbol)
                        .font(.title2)
                        .foregroundStyle(focus.phase.isBreak ? AnyShapeStyle(.teal) : AnyShapeStyle(Brand.gradient))
                    Text(Duration.seconds(remaining.rounded(.up)), format: .time(pattern: .minuteSecond))
                        .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                    Text(focus.session.taskTitle ?? focus.phase.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(40)
            }
            .frame(maxWidth: 320, maxHeight: 320)
            .accessibilityElement(children: .combine)
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 20) {
                Button("Reset", systemImage: "arrow.counterclockwise") { focus.reset() }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
                Button {
                    focus.toggle()
                } label: {
                    Image(systemName: focus.session.isRunning ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .frame(width: 88, height: 88)
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .glassEffect(.regular.tint(focus.phase.isBreak ? .teal : Brand.indigo).interactive(), in: .circle)
                .accessibilityLabel(focus.session.isRunning ? "Pause" : "Start")
                .sensoryFeedback(.impact, trigger: focus.session.isRunning)
                Button("Skip", systemImage: "forward.end.fill") { focus.skip() }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    private var sessionsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<focus.settings.dailyGoal, id: \.self) { i in
                    Circle()
                        .fill(i < focus.completedToday ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary.opacity(0.2)))
                        .frame(width: 12, height: 12)
                }
            }
            Text("\(focus.completedToday) of \(focus.settings.dailyGoal) sessions · \(focus.minutesToday) min focused today")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var taskPicker: some View {
        Menu {
            Button("No task") { focus.start(focus.phase, task: nil); focus.pause() }
            ForEach(tasks) { task in
                Button(task.title) {
                    if focus.session.isRunning { focus.reset() }
                    focus.start(.focus, task: task.title)
                    task.focusSessions += 1
                }
            }
        } label: {
            Label(focus.session.taskTitle ?? String(localized: "Focus on a task…"), systemImage: "checklist")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct FocusSettingsView: View {
    @Environment(FocusTimer.self) private var focus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var focus = focus
        NavigationStack {
            Form {
                Stepper("Focus: \(focus.settings.focusMinutes) min", value: $focus.settings.focusMinutes, in: 5...90, step: 5)
                Stepper("Short break: \(focus.settings.shortBreakMinutes) min", value: $focus.settings.shortBreakMinutes, in: 1...30)
                Stepper("Long break: \(focus.settings.longBreakMinutes) min", value: $focus.settings.longBreakMinutes, in: 5...60, step: 5)
                Stepper("Long break every \(focus.settings.sessionsBeforeLongBreak) sessions", value: $focus.settings.sessionsBeforeLongBreak, in: 2...8)
                Stepper("Daily goal: \(focus.settings.dailyGoal) sessions", value: $focus.settings.dailyGoal, in: 1...16)
            }
            .navigationTitle("Pomodoro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", role: .confirm) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
