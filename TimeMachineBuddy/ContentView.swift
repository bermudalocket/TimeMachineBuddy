//
//  ContentView.swift
//  TimeMachineBuddy
//  5.0
//  10.15
//
//  Created by bermudalocket on 6/19/20.
//  Copyright © 2020 bermudalocket. All rights reserved.
//

import ActivityIndicatorView
import SwiftUI
import Combine

struct ContentView: View {

    @ObservedObject var model = ContentViewModel()

    @State private var state = TimeMachineBackupState()

    @State private var isChecking = false

    private var formattedPercentage: String {
        if !self.state.isRunning {
            return "--%"
        }
        let pct = state.percentage.fractionDigitsRounded(to: 4, roundingMode: .halfUp)
        let pctInt = (Double(pct) ?? -1) * 100
        let pctIntFmt = pctInt.fractionDigitsRounded(to: 2, roundingMode: .halfUp)
        return "\(pctIntFmt)%"
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("Time Machine Buddy").font(.largeTitle).fontWeight(.black)
                Spacer()
            }
            if !self.state.isRunning {
                Spacer()
                Text("No Time Machine tasks are currently running.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .foregroundColor(Color(red: 242, green: 242, blue: 247))
                    VStack(alignment: .leading, spacing: 4) {
                        Group {
                            Text("Backing up to ") + Text(self.state.destUUID).bold() + Text(".")
                        }.font(.subheadline)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .foregroundColor(Color(.quaternaryLabelColor))
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .foregroundColor(.accentColor)
                                    .frame(width: geo.size.width * CGFloat(self.state.percentage))
                                HStack {
                                    Spacer()
                                    Text(self.formattedPercentage)
                                        .font(.footnote)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                    Spacer()
                                        .frame(width: geo.size.width * (1 - CGFloat(self.state.percentage)))
                                }
                            }
                        }
                        .frame(height: 16)
                        HStack {
                            Text("\(self.state.filesCopied) (+\(self.state.filesCopiedDelta))").bold()
                                + Text(" files copied (of \(self.state.totalFiles))")
                            Spacer()
                            Text("\(self.state.bytesCopied/1_000_000_000)GB").bold() + Text(" / \(self.state.totalBytes/1_000_000_000)GB")
                        }.font(.caption)
                        Text("Approximately ") + Text("\(self.state.timeRemaining/60) minutes").bold() + Text(" remaining.")
                    }.padding(12)
                }.frame(height: 80)
            }

            Spacer()
        }
        .frame(maxHeight: 160)
        .padding(.horizontal).padding(.bottom)
        .onReceive(self.model.$backupState) { state in
            self.state = state
        }
        .onReceive(self.model.$isChecking) { isChecking in
            self.isChecking = isChecking
        }
    }
}

struct TimeMachineBackupState {
    var isRunning = false
    var percentage: Double = 0
    var timeRemaining: Int = 0
    var destUUID = "None"
    var filesCopied: Int = 0
    var totalFiles: Int = 0
    var filesCopiedDelta: Int = 0
    var bytesCopied: Int = 0
    var totalBytes: Int = 0
}

class ContentViewModel: ObservableObject {

    @Published var isChecking = false

    @Published var backupState = TimeMachineBackupState()

    private var cancellable: AnyCancellable?

    private var timerCancellable: AnyCancellable?

    init() {
        self.timerCancellable = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.isChecking = true
                self?.askTimeMachineForUpdate()
            }
        self.askTimeMachineForUpdate()
    }

    func askTimeMachineForUpdate() {
        let task = Process()
        task.launchPath = "/usr/bin/tmutil"
        task.arguments = ["status"]
        task.terminationHandler = { task in
            print("done")
        }
        self.route(task)
        task.launch()
        task.waitUntilExit()
    }

    func route(_ process: Process) {
        let pipe = Pipe()
        process.standardOutput = pipe
        pipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        self.cancellable = NotificationCenter.default
            .publisher(for: .NSFileHandleDataAvailable, object: pipe.fileHandleForReading)
            .map { _ in
                String(data: pipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            }.sink { info in
                let lines = info.split(separator: "\n")
                guard lines.count > 6 else {
                    self.isChecking = false
                    self.backupState.isRunning = false
                    return
                }

                // destination uuid
                let id = lines[5]
                    .replacingOccurrences(of: "DestinationID = \"", with: "")
                    .replacingOccurrences(of: "\";", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // percentage
                let percent = lines[8]
                    .replacingOccurrences(of: "Percent = \"", with: "")
                    .replacingOccurrences(of: "\";", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // time remaining
                let time = lines[9]
                    .replacingOccurrences(of: "TimeRemaining = ", with: "")
                    .replacingOccurrences(of: ";", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // files
                let files = lines[13]
                    .replacingOccurrences(of: "files = ", with: "")
                    .replacingOccurrences(of: ";", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let filesCopied = Int(files) ?? 0

                // total files
                let totalFiles = lines[15]
                    .replacingOccurrences(of: "totalFiles = ", with: "")
                    .replacingOccurrences(of: ";", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // bytes
                let bytes = lines[12]
                    .replacingOccurrences(of: "bytes = ", with: "")
                    .replacingOccurrences(of: ";", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let bytesCopied = Int(bytes) ?? 0

                // total files
                let totalBytes = lines[14]
                    .replacingOccurrences(of: "totalBytes = ", with: "")
                    .replacingOccurrences(of: ";", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let totalBytesInt = Int(totalBytes) ?? 0

                self.backupState = TimeMachineBackupState(isRunning: true,
                                                    percentage: Double(percent) ?? -1,
                                                    timeRemaining: Int(time) ?? -1,
                                                    destUUID: id,
                                                    filesCopied: filesCopied,
                                                    totalFiles: Int(totalFiles) ?? -1,
                                                    filesCopiedDelta: filesCopied - self.backupState.filesCopied,
                                                    bytesCopied: bytesCopied,
                                                    totalBytes: totalBytesInt)
            }
    }

}

extension Formatter {
    static let number = NumberFormatter()
}

extension FloatingPoint {
    func fractionDigitsRounded(to digits: Int, roundingMode:  NumberFormatter.RoundingMode = .halfEven) -> String {
        Formatter.number.roundingMode = roundingMode
        Formatter.number.minimumFractionDigits = digits
        Formatter.number.maximumFractionDigits = digits
        return Formatter.number.string(for:  self) ?? ""
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
