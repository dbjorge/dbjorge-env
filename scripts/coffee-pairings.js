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
    return new Set(config.history
        .flatMap(historyEntry => historyEntry.pairing)
        .map(pair => orderPairLexically(...pair.split('/'))));
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

function orderPairLexically(person1, person2) {
    return person1 <= person2 ? `${person1}/${person2}` : `${person2}/${person1}`;
}

function makePairingFromListOrder(people) {
    const pairing = [];
    for (let i = 0; i < people.length; i += 2) {
        pairing.push(orderPairLexically(people[i], people[i+1]));
    }
    return pairing;
}

function findWildcardPairee(pairing) {
    const wildcardPair = pairing.find(pair => pair.includes('<wildcard>'));
    const pairees = wildcardPair.split('/');
    return pairees[0] === '<wildcard>' ? pairees[1] : pairees[0];
}

// This maintains which people are paired together, but updates the order in
// which they are presented to try to prefer avoiding making folks be meeting-schedulers
// (ie, listed first) 2 weeks in a row where possible.
function orderPairs(pairing, config) {
    let previousSchedulers = [];
    if (config.history.length > 0) {
        const previousPairing = config.history[config.history.length - 1].pairing;
        previousSchedulers = previousPairing.map(pair => pair.split('/')[0]);
    }
    
    const orderedPairing = pairing.map(pair => {
        const [a, b] = pair.split('/');
        const aScheduledPreviously = previousSchedulers.includes(a);
        const bScheduledPreviously = previousSchedulers.includes(b);
        if (aScheduledPreviously && !bScheduledPreviously) {
            console.log(`forcing pair order ${b}/${a}`);
            return `${b}/${a}`;
        } else if(bScheduledPreviously && !aScheduledPreviously) {
            console.log(`forcing pair order ${a}/${b}`);
            return `${a}/${b}`;
        } else {
            return Math.random() < .5 ? `${a}/${b}` : `${b}/${a}`
        }        
    });

    orderedPairing.sort();
    return orderedPairing;
}

function main() {
    const config = readConfigSync();
    let usedPairs = getUsedPairsFromHistory(config);
    let people = config.people;
    const includeWildcard = people.length % 2 === 1;
    if (includeWildcard) {
        people = [...people, '<wildcard>']
    }

    let attemptsSinceDeletingOldestPairing = 0;
    do {
        shuffleInPlace(people);
        const candidatePairing = makePairingFromListOrder(people);
        const reusesSomePair = candidatePairing.some(pair => usedPairs.has(pair));
        
        if (!reusesSomePair) {
            const finalizedPairing = orderPairs(candidatePairing, config);

            appendPairingToHistory(config, finalizedPairing);
            const listFormattedPairing = finalizedPairing
                .map(pair => '  - ' + pair)
                .join("\n");

            let wildcardMessage = '';
            if (includeWildcard) {
                wildcardPerson = findWildcardPairee(finalizedPairing)
                wildcardMessage = `
${wildcardPerson}, you are this week's wildcard! You may choose to either skip this week or pick any other person in the group to ask about a second coffee chat.
`;
            }

            const formattedDate = new Intl.DateTimeFormat('en').format(new Date());
            const suggestedSubject = `Accessibility Insights Coffee Chat pairs (week of ${formattedDate})`;
            const suggestedMessage = `
Hi all!

This week's suggested coffee pairs are:

${listFormattedPairing}

If you are the *first* name listed in a pair, please create your pair's meeting sometime this week.
${wildcardMessage}
Thanks!
-Dan
            `;

            console.log('=== SUGGESTED SUBJECT ===');
            console.log(suggestedSubject);
            console.log('=== SUGGESTED MESSAGE ===');
            console.log(suggestedMessage);
            break;
        }

        attemptsSinceDeletingOldestPairing++;
        if (attemptsSinceDeletingOldestPairing > 1000) {
            const deletedTimestamp = deleteOldestPairingFromHistory(config);
            console.log(`Could not find a non-repeating pairing; purging old pairing from ${deletedTimestamp}`);
            attemptsSinceDeletingOldestPairing = 0;
            usedPairs = getUsedPairsFromHistory(config);
        }
    } while(true);
}

main();
