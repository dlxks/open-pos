class ModifierOption {
  const ModifierOption({
    required this.id,
    required this.name,
    this.priceDeltaCents = 0,
  });

  final String id;
  final String name;
  final int priceDeltaCents;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'priceDeltaCents': priceDeltaCents,
  };

  factory ModifierOption.fromJson(Map<String, Object?> json) {
    final option = ModifierOption(
      id: json['id'] as String,
      name: json['name'] as String,
      priceDeltaCents: json['priceDeltaCents'] as int? ?? 0,
    );
    if (option.id.trim().isEmpty ||
        option.name.trim().isEmpty ||
        option.name.length > 80 ||
        option.priceDeltaCents.abs() > 9007199254740991) {
      throw const FormatException('Modifier option data is invalid.');
    }
    return option;
  }
}

class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    required this.options,
    this.minimumSelections = 0,
    this.maximumSelections = 1,
  });

  final String id;
  final String name;
  final List<ModifierOption> options;
  final int minimumSelections;
  final int maximumSelections;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'minimumSelections': minimumSelections,
    'maximumSelections': maximumSelections,
    'options': options.map((option) => option.toJson()).toList(),
  };

  factory ModifierGroup.fromJson(Map<String, Object?> json) {
    final options = (json['options'] as List<Object?>)
        .map((row) => ModifierOption.fromJson(row! as Map<String, Object?>))
        .toList(growable: false);
    final group = ModifierGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      minimumSelections: json['minimumSelections'] as int? ?? 0,
      maximumSelections: json['maximumSelections'] as int? ?? 1,
      options: List.unmodifiable(options),
    );
    final optionIds = options.map((option) => option.id).toSet();
    if (group.id.trim().isEmpty ||
        group.name.trim().isEmpty ||
        group.name.length > 80 ||
        group.minimumSelections < 0 ||
        group.maximumSelections < 1 ||
        group.minimumSelections > group.maximumSelections ||
        group.maximumSelections > options.length ||
        options.isEmpty ||
        optionIds.length != options.length) {
      throw const FormatException('Modifier group data is invalid.');
    }
    return group;
  }
}

class SelectedModifier {
  const SelectedModifier({
    required this.groupId,
    required this.groupName,
    required this.optionId,
    required this.name,
    required this.priceDeltaCents,
  });

  final String groupId;
  final String groupName;
  final String optionId;
  final String name;
  final int priceDeltaCents;

  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'groupName': groupName,
    'optionId': optionId,
    'name': name,
    'priceDeltaCents': priceDeltaCents,
  };

  factory SelectedModifier.fromJson(Map<String, Object?> json) {
    final modifier = SelectedModifier(
      groupId: json['groupId'] as String,
      groupName: json['groupName'] as String,
      optionId: json['optionId'] as String,
      name: json['name'] as String,
      priceDeltaCents: json['priceDeltaCents'] as int,
    );
    if (modifier.groupId.trim().isEmpty ||
        modifier.groupName.trim().isEmpty ||
        modifier.optionId.trim().isEmpty ||
        modifier.name.trim().isEmpty) {
      throw const FormatException('Selected modifier data is invalid.');
    }
    return modifier;
  }
}
