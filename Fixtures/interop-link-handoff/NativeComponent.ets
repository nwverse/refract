// Application-owned source contract, not compiled with a HarmonyOS toolchain here.
export type LinkDestinationKind = 'external' | 'deepLink';

export type LinkHandoffResult = 'handedOff' | 'cancelled' | 'disallowed' | 'unsupportedScheme' | 'unavailable';

export type LinkHandoffCompletion = (result: LinkHandoffResult) => void;

export class LinkDestination {
  public readonly kind: LinkDestinationKind;
  public readonly scheme: string;
  public readonly host: string;
  public readonly path: string;

  constructor(kind: LinkDestinationKind, scheme: string, host: string, path: string) {
    this.kind = kind;
    this.scheme = scheme;
    this.host = host;
    this.path = path;
  }
}

export class LinkAllowlistEntry {
  public readonly scheme: string;
  public readonly host: string;

  constructor(scheme: string, host: string) {
    this.scheme = scheme;
    this.host = host;
  }
}

export class LinkPolicy {
  public readonly allowed: LinkAllowlistEntry[];

  constructor(allowed: LinkAllowlistEntry[]) {
    this.allowed = allowed;
  }

  public permits(destination: LinkDestination): boolean {
    return this.allowed.some((entry: LinkAllowlistEntry): boolean =>
      entry.scheme === destination.scheme && entry.host === destination.host);
  }
}

export interface LinkHandoff {
  begin(destination: LinkDestination, completion: LinkHandoffCompletion): void;
  cancel(destination: LinkDestination): void;
}

/** The app implements this component with native confirmation and its own router/lifecycle. */
@ComponentV2
export struct NativeHelpLink {
  @Require @Param public var destination: LinkDestination;
  @Require @Param public var policy: LinkPolicy;
  @Require @Param public var handoff: LinkHandoff;

  build() {
    // Keep native confirmation, cancellation, router and page lifecycle in this implementation.
  }
}
