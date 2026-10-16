# Creative tendencies and descriptive history

Vellum distinguishes; Moss notices temporal and sonic consequence; Morrow infers hidden properties from evidence; Knurl makes affordances playable; Sable interrogates protocols; Pica studies specimens; Oriel maps systems and their failures. Members may use any valid medium.

The ideation order is notice, question, mechanism, artefact, then metadata. Weekly words remain optional. History reports describe habits without quotas, forced rotation or automatic balancing.

`system/schemas/creative-vocabulary.json` defines controlled metadata and each member's moves. `system/creative.lua` validates it, creates member-specific proposal schemas and generates deterministic statistics. `creative_form` describes the artwork; the existing `form` still selects its technical build route. Optional scale metadata is deferred.

New proposals and manifests carry member_move, creative_form, source_domain, sensory_mode, dimensionality, temporal_mode, agency and randomness. New manifests use metadata_version 1; their fields must match the accepted proposal. Catalogue publication retains these fields. The manifest schema documents the new contract; runtime checks enforce vocabulary, member ownership and proposal equality.

Ideation receives counts over the latest fourteen completed catalogue entries plus the member's last three creative forms and last five moves, newest first. Unknown historical values count explicitly as unknown. Old archives and catalogue rows are not backfilled or rewritten. Legacy manifests without any creative metadata remain readable; partially supplied or invalid metadata fails validation.

No model route, budget, heartbeat frequency, publication transaction or Defold architecture changes are required. Publication only copies the extra metadata into catalogue rows.

Builders and repair sessions also receive the member voice while keeping the accepted idea and metadata fixed. Validation: 45 offline acceptance tests pass, including an entire synthetic week, metadata publication and tamper rejection, member-specific schemas, legacy compatibility, deterministic history windows and preservation of optional weekly words. Tests use disposable repositories and block live model executables.
