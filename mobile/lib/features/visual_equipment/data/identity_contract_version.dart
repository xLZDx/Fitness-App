/// Version constants for the P2.G4 equipment-identity contract
/// (functions-equipment-identity/src/p2/contract.ts).
///
/// ## Why these are app-owned, not the raw ML Kit package version
///
/// `kOcrAuthorityEpoch` names the OCR *behavior* this client's parsing
/// (P2.G2's `parseIdentityText`) was built and tested against, not
/// `google_mlkit_text_recognition`'s own pubspec version. A ML Kit patch
/// bump the app never re-validated against would otherwise silently claim
/// an authority tuple it does not actually have evidence for -- the server
/// records this string verbatim in `authority.ocrVersion` and treats it as
/// a durable claim about what produced the evidence (GPT-PM round-2/round-3
/// requirement, P2.G4 Rosetta plan rev4).
const String kMobileIdentityContractVersion = 'v1';

const String kOcrAuthorityEpoch = 'p2g1-mlkit-latin-structured-v1';

const String kIdentityParserEpoch = 'p2g2-identity-parser-v1';
