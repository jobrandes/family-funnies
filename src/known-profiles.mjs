// Group the picker only; source profiles and photos remain independent.
export function profileKey(profile) {
  return `${profile.kind || 'person'}:${String(profile.name || '').normalize('NFKC').trim().replace(/\s+/g, ' ').toLocaleLowerCase('en-US')}`;
}

export function groupKnownProfiles(profiles) {
  const groups = new Map();
  for (const profile of profiles) {
    const key = profileKey(profile);
    if (!groups.has(key)) groups.set(key, {key, name: profile.name, sources: []});
    groups.get(key).sources.push(profile);
  }
  return [...groups.values()];
}
