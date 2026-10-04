/** User-authored instructions. Only the catalog is disclosed until read_skill is called. */
export interface UserSkill {
  id: string;
  name: string;
  description: string;
  body: string;
  enabled: boolean;
}

export const SKILL_NAME_LIMIT = 60;
export const SKILL_DESCRIPTION_LIMIT = 200;
export const SKILL_BODY_LIMIT = 4000;

export interface SkillErrors {
  name: string;
  description: string;
  body: string;
}

export function newSkill(): UserSkill {
  return {
    id: `${Date.now()}-${Math.random().toString(36).substring(2)}`,
    name: '', description: '', body: '', enabled: true
  };
}

export function copySkill(skill: UserSkill): UserSkill {
  return { id: skill.id, name: skill.name, description: skill.description, body: skill.body, enabled: skill.enabled };
}

export function validateSkill(skill: UserSkill, others: UserSkill[] = []): SkillErrors {
  const errors: SkillErrors = { name: '', description: '', body: '' };
  const name = skill.name.trim();
  const description = skill.description.trim();
  if (name.length === 0) {
    errors.name = 'Name is required.';
  } else if (name.length > SKILL_NAME_LIMIT) {
    errors.name = `Name must be at most ${SKILL_NAME_LIMIT} characters.`;
  } else if (others.some((other: UserSkill) => other.id !== skill.id && other.name.trim().toLowerCase() === name.toLowerCase())) {
    errors.name = 'A skill with this name already exists.';
  }
  if (description.length === 0) {
    errors.description = 'Description is required.';
  } else if (description.length > SKILL_DESCRIPTION_LIMIT) {
    errors.description = `Description must be at most ${SKILL_DESCRIPTION_LIMIT} characters.`;
  }
  if (skill.body.length > SKILL_BODY_LIMIT) {
    errors.body = `Body must be at most ${SKILL_BODY_LIMIT} characters.`;
  }
  return errors;
}

export function hasSkillErrors(errors: SkillErrors): boolean {
  return errors.name.length > 0 || errors.description.length > 0 || errors.body.length > 0;
}

/** Corrupt stores return an empty list; malformed rows and duplicate names/IDs are skipped. */
export function parseSkills(json: string): UserSkill[] {
  const skills: UserSkill[] = [];
  try {
    const parsed = JSON.parse(json) as Object;
    if (!Array.isArray(parsed)) {
      return skills;
    }
    for (const item of parsed as Object[]) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const row = item as Record<string, Object>;
      if (typeof row['id'] !== 'string' || typeof row['name'] !== 'string' ||
        typeof row['description'] !== 'string' || typeof row['body'] !== 'string' || typeof row['enabled'] !== 'boolean') {
        continue;
      }
      const skill: UserSkill = {
        id: (row['id'] as string).trim(), name: (row['name'] as string).trim(),
        description: (row['description'] as string).trim(), body: row['body'] as string, enabled: row['enabled'] as boolean
      };
      if (skill.id.length === 0 || skills.some((other: UserSkill) => other.id === skill.id) ||
        hasSkillErrors(validateSkill(skill, skills))) {
        continue;
      }
      skills.push(skill);
    }
  } catch (error) {
    return [];
  }
  return skills;
}

export function serializeSkills(skills: UserSkill[]): string {
  return JSON.stringify(skills.map((skill: UserSkill) => {
    const normalized = copySkill(skill);
    normalized.name = normalized.name.trim();
    normalized.description = normalized.description.trim();
    return normalized;
  }));
}

/** A detached snapshot: later edits to the settings must not change an active run. */
export function enabledSkills(skills: UserSkill[]): UserSkill[] {
  return skills.filter((skill: UserSkill) => skill.enabled).map((skill: UserSkill) => copySkill(skill));
}

export function findSkill(skills: UserSkill[], name: string): UserSkill | undefined {
  const key = name.trim().toLowerCase();
  return skills.find((skill: UserSkill) => skill.enabled && skill.name.toLowerCase() === key);
}

export function skillPromptSection(skills: UserSkill[]): string {
  const active = enabledSkills(skills);
  if (active.length === 0) {
    return '';
  }
  const catalog = active.map((skill: UserSkill) =>
    `- ${skill.name.replace(/[\r\n]+/g, ' ')}: ${skill.description.replace(/[\r\n]+/g, ' ')}`).join('\n');
  return '\n\nSkills\nThese skills contain the user\'s instructions for specific apps or tasks. ' +
    'Before acting on a task covered by a skill, use read_skill to load its full instructions and follow them. ' +
    'The current task takes precedence if it conflicts with a skill.\n' + catalog;
}
