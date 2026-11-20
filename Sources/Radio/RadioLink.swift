// RadioLink.swift
//
// What RadioMonitor and RadioControl need from a radio, however it's
// reached: through a rigctld you run (RigctldClient, Hamlib NET rigctl), or
// through the built-in driver for Kenwood-protocol radios (KenwoodClient). Both take
// the same command strings from RadioControl ("F 7025300", "M CW 500",
// "POWER 5"), so the rest of the app doesn't know which one is in use.

import Foundation

protocol RadioLink: AnyObject, Sendable {
    // Frequency, mode, power (and the filter width, if the radio has one).
    func reading() throws -> RadioReading
    // The status line's settings, asked for mode `mode` (see RigctldClient).
    func status(mode: String) throws -> RadioStatus
    // The S-meter, in decibels above S9.
    func strength() throws -> Int
    // Tries each command in turn until the radio takes one, and returns it.
    func setFirst(of commands: [String]) throws -> String
    // Closes the connection. The next call opens it again.
    func disconnect()
}

// Why a radio call failed. RadioMonitor says each kind differently.
enum RadioFailure: Error, Equatable {
    // Nothing is listening at the rigctld address: rigctld isn't running.
    case notRunning
    // The radio (or rigctld) didn't answer: it's off, or the speed or model
    // is wrong.
    case notAnswering
    // The radio (or hamlib) said no: it can't do that, or not now.
    case rejected
    // The radio's serial port has gone (the radio is off or unplugged).
    // Only the built-in driver sees this: rigctld does its own checking.
    case portGone
    // Another app has the serial port open, so Solid Copy can't.
    case portBusy
}
