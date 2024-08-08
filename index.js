#!/bin/env node

const fs = require("fs");
const midiParser  = require("midi-parser-js");

function midiParse(midiData) {
	midiData = midiParser.parse(midiData);
	const ppq = midiData.timeDivision;
	// set absolute times in each track
	// add instrument names
	for (const track of midiData.track) {
		let instrument = "unknown";
		let time = 0;
		let tempo = 500000;
		for (const event of track.event) {
			if (event.type === 255) {
				switch (event.metaType) {
					case 3:
						instrument = event.data;
						break;
					case 81:
						tempo = event.data;
						break;
				}
			}
			event.time = time;
			event.instrument = instrument;
			event.tempo = tempo;
			time += event.deltaTime;
		}
	}
	// combine tracks
	midiData.event = midiData.track.flatMap(track => track.event);
	midiData.event.sort((a, b) => a.time - b.time);
	delete midiData.track;
	// take useful data
	// fix delta
	const out = [];
	let lastTime = 0;
	for (const event of midiData.event) {
		if (event.type != 9) continue;
		if (!event.data) continue;
		if (event.data[1] <= 0) continue; // note off
		let delta = (event.time - lastTime) * (event.tempo / ppq / 1000);
		out.push({
			note: event.data[0],
			instrument: event.instrument,
			delta,
		});
		lastTime = event.time;
	}
	return out;
}

NOTEBLOCKSOUNDS = ["stop", "nothing", "harp", "basedrum", "snare", "hat", "bass", "flute", "bell", "guitar", "chime", "xylophone", "iron_xylophone", "cow_bell", "didgeridoo", "banjo", "pling"];
function instrument2noteblock(instrument) {
	instrument = String(instrument).toLowerCase();
	if (instrument.indexOf("harp") != -1 || instrument.indexOf("piano") != -1)
		return "harp";
	if (instrument.indexOf("basedrum") != -1)
		return "basedrum";
	if (instrument.indexOf("snare") != -1 || instrument.indexOf("drum") != -1)
		return "snare";
	if (instrument.indexOf("hat") != -1)
		return "hat";
	if (instrument.indexOf("bass") != -1)
		return "bass";
	if (instrument.indexOf("flute") != -1 || instrument.indexOf("wind") != -1 || instrument.indexOf("whistle") != -1)
		return "flute";
	if (instrument.indexOf("bell") != -1)
		return "bell";
	if (instrument.indexOf("guitar") != -1 || instrument.indexOf("banjo") != -1)
		return "guitar";
	if (instrument.indexOf("chime") != -1)
		return "chime";
	if (instrument.indexOf("xylophone") != -1)
		return "xylophone";
	if (instrument.indexOf("iron xylophone") != -1)
		return "iron_xylophone";
	if (instrument.indexOf("cow bell") != -1)
		return "cow_bell";
	if (instrument.indexOf("didgeridoo") != -1)
		return "didgeridoo";
	if (instrument.indexOf("pling") != -1 || instrument.indexOf("synth") != -1 || instrument.indexOf("choir") != -1)
		return "pling";
	return "harp";
}

function midi2mccc(midiParsed) {
	// get average duration and correct for tick speed (0.05s / tick)
	let deltaAvg = 0;
	let deltaCnt = 0;
	for (const event of midiParsed) {
		if (event.delta <= 0) continue;
		deltaAvg += event.delta;
		deltaCnt++;
	}
	deltaAvg /= deltaCnt;
	// nearest 0.05s
	const deltaAvgRounded = Math.ceil(deltaAvg / 1000 * 20) / 20 * 1000; 
	const deltaMul = deltaAvgRounded / deltaAvg;
	// convert instruments to noteblock types
	// get duration
	const instruments = {};
	let duration = 0;
	for (const event of midiParsed) {
		event.delta *= deltaMul;
		duration += event.delta;
		if (instruments[event.instrument]) continue;
		instruments[event.instrument] = NOTEBLOCKSOUNDS.indexOf(instrument2noteblock(event.instrument));
	}
	duration = Math.ceil(duration);
	// find most common note
	let sum = 0;
	for (const event of midiParsed) sum += event.note;
	const avg = Math.round(sum / midiParsed.length);
	const offset = 12 - avg;
	// instruments
	const buffer = new Uint8Array(midiParsed.length * 4 + 4 + 4 + 4);
	let i = 0;
	buffer[i++] = "MDMC".charCodeAt(0);
	buffer[i++] = "MDMC".charCodeAt(1);
	buffer[i++] = "MDMC".charCodeAt(2);
	buffer[i++] = "MDMC".charCodeAt(3);
	buffer[i++] = duration >> 24;
	buffer[i++] = (duration >> 16) & 0xFF;
	buffer[i++] = (duration >> 8) & 0xFF;
	buffer[i++] = duration & 0xFF;
	for (const event of midiParsed) {
		let note = event.note + offset;
		while (note < 0) note += 12;
		while (note > 24) note -= 12;
		buffer[i++] = instruments[event.instrument];
		buffer[i++] = Math.round(event.delta) >> 8;
		buffer[i++] = Math.round(event.delta) & 0xFF;
		buffer[i++] = note;
	}
	buffer[i++] = 0; buffer[i++] = 0; buffer[i++] = 0; buffer[i++] = 0;
	console.error(`Duration: ${duration} Speed: ${1 / deltaMul}x`);
	return buffer;
}

const filein = process.argv[2];
const fileout = process.argv[3];
if (!filein || !fileout) process.exit("Usage: node index.js <midi-in-file> <mdmc-out-file>");
console.error(`${filein} -> ${fileout}`);
const midiData = fs.readFileSync(filein);
const midiParsed = midiParse(midiData);
const midiBuffer = midi2mccc(midiParsed);

fs.writeFileSync(fileout, Buffer.from(midiBuffer));
