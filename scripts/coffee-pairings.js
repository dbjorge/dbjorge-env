const fs = require('fs');
const path = require('path');
const { stringify } = require('querystring');

function readConfigSync() {
    const rawContent = fs.readFileSync(path.join(__dirname, 'coffee-pairings.config.jsonc'));
    return JSON.parse(rawContent.toString());
}

function writeConfigSync(config) {
    fs.writeFileSync('./coffee-pairings.config.jsonc', JSON.stringify(config, null, 4));
}

function getUsedPairsFromHistory(config) {
    return new Set(config.history.flatMap(historyEntry => historyEntry.pairing));
}

function appendPairingToHistory(config, newPairing) {
    config.history.push({
        timestamp: new Date().toISOString(),
        pairing: newPairing,
    });
    writeConfigSync(config);
}

function deleteOldestPairingFromHistory(config) {
    const oldestTimestamp = config.history[0].timestamp;
    config.history.shift();
    writeConfigSync(config);
    return oldestTimestamp;
}

function shuffleInPlace(array) {
    for (let i = array.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [array[i], array[j]] = [array[j], array[i]];
    }
    return array;
}

function makePairId(person1, person2) {
    return person1 <= person2 ? `${person1}/${person2}` : `${person2}/${person1}`;
}

function randomizePairIdOrder(pairId) {
    [person1, person2] = pairId.split('/');
    return Math.random() < .5 ? `${person1}/${person2}` : `${person2}/${person1}`
}

function makeInOrderPairing(people) {
    const pairing = [];
    for (let i = 0; i < people.length; i += 2) {
        pairing.push(makePairId(people[i], people[i+1]));
    }
    return pairing;
}

function main() {
    const config = readConfigSync();
    let people = config.people;
    if (people.length % 2 == 1) {
        people = [...people, '<noone>']
    }

    let attemptsSinceDeletingOldestPairing = 0;
    do {
        const usedPairs = getUsedPairsFromHistory(config);
        shuffleInPlace(people);
        const candidatePairing = makeInOrderPairing(people);
        const reusesSomePair = candidatePairing.some(pair => usedPairs.has(pair));
        
        if (!reusesSomePair) {
            candidatePairing.sort();
            appendPairingToHistory(config, candidatePairing);
            console.log('== Suggested pairing ==');
            for (const pair of candidatePairing) {
                console.log(randomizePairIdOrder(pair));
            }
            break;
        }

        attemptsSinceDeletingOldestPairing++;
        if (attemptsSinceDeletingOldestPairing > 1000) {
            const deletedTimestamp = deleteOldestPairingFromHistory(config);
            console.log(`Could not find a non-repeating pairing; purging old pairing from ${deletedTimestamp}`);
            attemptsSinceDeletingOldestPairing = 0;
        }
    } while(true);
}

main();
