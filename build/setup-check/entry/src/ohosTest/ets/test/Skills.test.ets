import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { preferences } from '@kit.ArkData';
import { loadSkills, saveSkills } from '../../../main/ets/common/Settings';
import {
  enabledSkills, findSkill, hasSkillErrors, parseSkills, serializeSkills, skillPromptSection, UserSkill, validateSkill
} from '../../../main/ets/agent/Skills';

function skill(id: string = '1', name: string = 'Calendar'): UserSkill {
  return { id: id, name: name, description: 'Creating calendar events', body: 'Use a 90-minute duration.\nKeep the title.', enabled: true };
}

export default function skillsTest() {
  describe('Skills', () => {
    it('persists skills in settings, reloads without cache, and tolerates a corrupt store', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.hackyeah.phoneagent', abilityName: 'EntryAbility' });
      const ability = await delegator.getCurrentTopAbility();
      const context = ability.context;
      const initial = preferences.getPreferencesSync(context, { name: 'settings' });
      const existed = initial.hasSync('skills');
      const previous = initial.getSync('skills', '[]');
      try {
        await saveSkills(context, [skill()]);
        expect(loadSkills(context, true)[0].body).assertContain('90-minute');
        const fresh = preferences.getPreferencesSync(context, { name: 'settings' });
        fresh.putSync('skills', '{broken');
        await fresh.flush();
        expect(loadSkills(context, true).length).assertEqual(0);
      } finally {
        const restore = preferences.getPreferencesSync(context, { name: 'settings' });
        if (existed) {
          restore.putSync('skills', previous);
        } else {
          restore.deleteSync('skills');
        }
        await restore.flush();
      }
    });

    it('round-trips Unicode and multiline instructions without changing their body', 0, () => {
      const original = skill('1', 'Kalendarz');
      original.body = '  Wydarzenia: impreza\nZażółć gęślą jaźń.  ';
      const parsed = parseSkills(serializeSkills([original]));
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].body).assertEqual(original.body);
      expect(parsed[0].enabled).assertTrue();
    });

    it('returns an empty list for corrupt JSON and non-array values', 0, () => {
      for (const json of ['broken', '{', 'null', '{}', '"text"', '42']) {
        expect(parseSkills(json).length).assertEqual(0);
      }
    });

    it('skips malformed rows while keeping valid skills', 0, () => {
      const json = `[null,42,[],{},${serializeSkills([skill()]).substring(1)}`;
      const parsed = parseSkills(json);
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].name).assertEqual('Calendar');
      expect(parseSkills('[{"id":"1","name":"x","description":"d","body":42,"enabled":true}]').length).assertEqual(0);
    });

    it('requires names and descriptions but permits an empty body', 0, () => {
      const draft = skill();
      draft.name = '  ';
      draft.description = '';
      const errors = validateSkill(draft);
      expect(errors.name).assertContain('required');
      expect(errors.description).assertContain('required');
      draft.name = 'Calendar';
      draft.description = 'Events';
      draft.body = '';
      expect(hasSkillErrors(validateSkill(draft))).assertFalse();
    });

    it('accepts exact length limits and rejects longer values', 0, () => {
      const draft = skill();
      draft.name = 'n'.repeat(60);
      draft.description = 'd'.repeat(200);
      draft.body = 'b'.repeat(4000);
      expect(hasSkillErrors(validateSkill(draft))).assertFalse();
      draft.name += 'n';
      draft.description += 'd';
      draft.body += 'b';
      const errors = validateSkill(draft);
      expect(errors.name).assertContain('60');
      expect(errors.description).assertContain('200');
      expect(errors.body).assertContain('4000');
    });

    it('allows changing the case of its own name and rejects case-insensitive duplicates', 0, () => {
      expect(hasSkillErrors(validateSkill(skill('1', 'CALENDAR'), [skill()]))).assertFalse();
      expect(validateSkill(skill('2', ' calendar '), [skill()]).name).assertContain('already exists');
      expect(parseSkills(serializeSkills([skill(), skill('2', 'CALENDAR'), skill('1', 'Other')])).length).assertEqual(1);
    });

    it('normalizes name and description but keeps body whitespace', 0, () => {
      const draft = skill('1', ' Calendar ');
      draft.description = ' Events ';
      expect(parseSkills(serializeSkills([draft]))[0].name).assertEqual('Calendar');
      expect(parseSkills(serializeSkills([draft]))[0].description).assertEqual('Events');
    });

    it('discloses only enabled names and descriptions, never the body', 0, () => {
      const hidden = skill('2', 'Hidden');
      hidden.enabled = false;
      const section = skillPromptSection([skill(), hidden]);
      expect(section).assertContain('- Calendar: Creating calendar events');
      expect(section).assertContain('read_skill');
      expect(section.includes('Hidden')).assertFalse();
      expect(section.includes('90-minute')).assertFalse();
      expect(skillPromptSection([hidden])).assertEqual('');
    });

    it('freezes the enabled snapshot and only resolves enabled names', 0, () => {
      const original = skill();
      const snapshot = enabledSkills([original]);
      original.body = 'changed';
      original.enabled = false;
      expect(snapshot[0].body).assertContain('90-minute');
      expect(findSkill(snapshot, 'CALENDAR')?.name).assertEqual('Calendar');
      expect(findSkill([original], 'Calendar')).assertUndefined();
    });
  });
}
