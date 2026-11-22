import { ComposerModel } from '../../../main/ets/generated/InteropTextInputHost';

/** The application, not the native host or generated screen, owns retention. */
@ObservedV2
export class ComposerDraftModel implements ComposerModel {
  @Trace lastSubmittedDraft: string = '';
  @Trace commitCount: number = 0;
  @Trace committedEventLog: string = '';
  private events: string[] = [];
  @Trace drafts: string[] = [];

  private recordCommittedEvent(value: string): void {
    this.events.push(value);
    // A replaced scalar is observed even when its containing model is @Local.
    this.committedEventLog = this.events.join(',');
  }

  commitDraft(value: string): void {
    this.lastSubmittedDraft = value;
    this.recordCommittedEvent(`draft:${value}`);
  }

  commit(): void {
    this.commitCount += 1;
    this.recordCommittedEvent('commit');
  }
}
