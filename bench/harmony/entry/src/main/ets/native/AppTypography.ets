export interface Font {
  size: number;
  weight: FontWeight;
}

// App-owned native typography; no runtime lookup or generated adapter.
export class AppTypography {
  static readonly screenTitle: Font = { size: 22, weight: FontWeight.Medium };
  static readonly rowTitle: Font = { size: 16, weight: FontWeight.Normal };
  static readonly rowSubtitle: Font = { size: 12, weight: FontWeight.Normal };
}
