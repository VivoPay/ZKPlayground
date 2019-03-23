//
//  Docker.swift
//  ZKPlayground
//
//  Created by Ronald "Danger" Mannak on 3/21/19.
//  Copyright © 2019 A Puzzle A Day. All rights reserved.
//

import Foundation

protocol DockerProtocol: class {
    
    // Docker received data from the docker image
    func docker(_ docker: Docker, didReceiveStdout string: String)
    
    // Docker received an error from the docker image
    func docker(_ docker: Docker, didReceiveStderr string: String)
    
    // Docker sent stdin to the docker image from the app
    func docker(_ docker: Docker, didReceiveStdin string: String)
}

class Docker: Operation {
    
    weak var delegate: DockerProtocol?
    
    /// If any of the commands in the script returns non-zero,
    /// the script will cancel and forward the exit code
    /// 0 is success, anything else is an error
    /// http://www.tldp.org/LDP/abs/html/exitcodes.html
    private (set) var exitStatus: Int?
    
    private let task = Process()
    
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe = Pipe()
    private var notifications = [NSObjectProtocol]()
    
    /// Path of the directory the .code file is in, e.g. "/MySource/"
    private let workDirectoryPath: String
    
    /// Name of the .code file, e.g. "HelloWorld.code"
    private let filename: String
    
    /// the name of the directory mapped to workDirectoryPath
    private static let dockerDirectoryPath = "/home/zokrates/playground"
    
    private var dockerFilename: String {
        return URL(fileURLWithPath: Docker.dockerDirectoryPath).appendingPathComponent(self.filename).path
    }
    
    init(workDirectory: String, filename: String) {
        
        self.workDirectoryPath = workDirectory
        self.filename = filename
    }
    
    /// Runs (and if needed, installs) Zokrates in a Docker image
    /// Format is: docker run -v /Users/davidhasselhoff/Code/:/home/zokrates/playground -i zokrates/zokrates /bin/bash
    override func main() {
        
        defer { _ = notifications.map { NotificationCenter.default.removeObserver($0) } }
        
        guard isCancelled == false else { return }
        
        // Set up task
        self.task.environment = ProcessInfo().environment
        self.task.environment?.updateValue("/usr/local/bin/:/usr/bin:/bin:/usr/sbin:/sbin", forKey: "PATH")
        task.launchPath = "/usr/local/bin/docker" // TODO: use which path
        task.arguments = ["run", "-v", self.workDirectoryPath + ":" + Docker.dockerDirectoryPath, "-i", "zokrates/zokrates", "/bin/bash"]
        task.currentDirectoryPath = Bundle.main.bundlePath
        
        // Print to log
        let command: String = task.launchPath ?? ""
        let arguments: String = task.arguments?.joined(separator: " ") ?? ""
        self.delegate?.docker(self, didReceiveStdin: "\n$ " + command + " " + arguments + "\n")
        
        // Set exitStatus at exit
        self.task.terminationHandler = { task in
            self.exitStatus = Int(task.terminationStatus)
            if self.exitStatus == 0 {
                self.delegate?.docker(self, didReceiveStdin: "Task exited with exit status 0\n")
            } else {
                self.delegate?.docker(self, didReceiveStderr: "Task exited with exit status \(self.exitStatus!)\n")
            }
            self.delegate?.docker(self, didReceiveStdout: "\(self.stdinPipe.fileHandleForWriting)")
        }
        
        // Handle I/O
        self.task.standardOutput = self.stdoutPipe
        self.task.standardError = self.stderrPipe
        self.task.standardInput = self.stdinPipe

        self.capture(self.stdoutPipe) { stdout in
            self.delegate?.docker(self, didReceiveStdout: stdout)
            
            // print utf8 values
//            var s = ""
//            _ = stdout.utf8.map{ s.append("\($0), ") }
//            self.delegate?.docker(self, didReceiveStdin: s)
        }
        self.capture(self.stderrPipe) { stderr in
            self.delegate?.docker(self, didReceiveStderr: stderr)
        }
        
        task.launch()
        task.waitUntilExit()
    }
    
    private func capture(_ pipe: Pipe, dataReceived: @escaping (String) -> Void) {
        
        let notification = NotificationCenter.default.addObserver(forName: .NSFileHandleDataAvailable, object: pipe.fileHandleForReading , queue: nil) { notification in
            
            let output = pipe.fileHandleForReading.availableData
            
            guard let outputString = String(data: output, encoding: String.Encoding.utf8), !outputString.isEmpty else { return }
            
            print(outputString)
            dataReceived(outputString)
            
            pipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        }
        
        notifications.append(notification)
            
        pipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
    }
    
    
    /// Compiles code, returns warnings and errors
    /// ./zokrates compile -i playground/root.code
    func compile() {
        
        let command = "./zokrates compile -i " + self.dockerFilename
        self.write(command)
    }
    
    /// Compiles and builds product and proofs
    func build() {
        
    }
    
    
    /// Will add newline character to string
    ///
    /// - Parameter string: <#string description#>
    func write(_ string: String) {
        
        let string = string + "\n"
        guard task.isRunning == true, let data = (string).data(using: .utf8) else { return assertionFailure() }
        print (string)
        self.delegate?.docker(self, didReceiveStdin: "\n" + string)
        self.stdinPipe.fileHandleForWriting.write(data)
        self.stdinPipe.fileHandleForWriting.waitForDataInBackgroundAndNotify()
    }
    
    /// Exits Docker
    override func cancel() {
        
        // Send 'exit' command to docker
        if task.isRunning { task.interrupt() }
        self.stdinPipe.fileHandleForReading.closeFile()
        self.stderrPipe.fileHandleForReading.closeFile()
        self.stdoutPipe.fileHandleForWriting.closeFile()
        super.cancel()
    }
}