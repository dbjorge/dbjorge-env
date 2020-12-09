// I use PowerShell's AzureAD module to generate this list:
// Get-AzureADGroupMembersRecursive -SearchString '<our team alias>' | % { $_.DisplayName.Split(' ')[0] } | sort
const people = [
    // regenerate this before running!
]

// returns an array of weekly pairings, where each week is represented
// as an array of pairIds. eg, getPairings(['a', 'b', 'c', 'd']) might return
// [
//    ['a/b', 'c/d'],
//    ['a/c', 'b/d'],
//    ['a/d', 'b/c'],
// ]
function getPairings(people) {
    const pairId = (person1, person2) => `${person1}/${person2}`;

    if (people.length % 2 == 1) {
        people = [...people, '<noone>']
    } 
    people = people.sort();
    
    const usedPairIds = new Set();
    const allWeeksPairings = {};
    for (let week = 1; week < people.length; week += 1) {
        const peopleStillToPair = [...people];
        const thisWeeksPairings = [];
        while (peopleStillToPair.length > 0) {
            const person1 = peopleStillToPair.splice(0, 1)[0];
            for (let person2index = 0; person2index < peopleStillToPair.length; person2index += 1) {
                const candidatePair = pairId(person1, peopleStillToPair[person2index],);
                if (!usedPairIds.has(candidatePair)) {
                    usedPairIds.add(candidatePair);
                    thisWeeksPairings.push(candidatePair);
                    peopleStillToPair.splice(person2index, 1)
                    break;
                }
            }
        }
        allWeeksPairings[`Week ${week}`] = thisWeeksPairings;
    }

    return allWeeksPairings;
}

const pairings = getPairings(people);
const formattedPairings = JSON.stringify(pairings, null, 2);
console.log(formattedPairings);
