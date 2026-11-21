import { ComposerModel } from '../../../main/ets/generated/InteropTextInputHost';

/** The application, not the native host or generated screen, owns retention. */
@ObservedV2
export class ComposerDraftModel implements ComposerModel {
  @Trace lastSubmittedDraft: string = '';
  @Trace commitCount: number = 0;
  @Trace events: string[] = [];
  @Trace drafts: string[] = [];

  commitDraft(value: string): void {
    this.lastSubmittedDraft = value;
    this.events.push(`draft:${value}`);
  }

  commit(): void {
    this.commitCount += 1;
    this.events.push('commit');
  }
}
