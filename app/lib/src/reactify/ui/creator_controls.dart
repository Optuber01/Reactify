import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../gacha/code/gacha_character_state.dart';
import '../../gacha/data/resolver_tables.dart';
import '../project/project_character.dart';

const _ink = Color(0xFF171A19);
const _panel = Color(0xFFF8F5EA);
const _line = Color(0xFF343936);
const _signal = Color(0xFFD4FF32);

class CharacterCreatorPanel extends StatelessWidget {
  const CharacterCreatorPanel({
    super.key,
    required this.tables,
    required this.character,
    required this.onNumericChanged,
    required this.onColorChanged,
  });

  final ResolverTables tables;
  final ProjectCharacter? character;
  final void Function(String field, int value) onNumericChanged;
  final void Function(String field, Color value) onColorChanged;

  @override
  Widget build(BuildContext context) {
    final selected = character;
    return Container(
      color: _panel,
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: _line)),
      ),
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: const Text(
              '02   CHARACTER CREATOR',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                fontSize: 12,
              ),
            ),
          ),
          if (selected == null)
            const Expanded(child: Center(child: Text('NO ACTIVE CHARACTER')))
          else
            Expanded(
              child: DefaultTabController(
                length: _tabs.length,
                child: Column(
                  children: [
                    _Identity(character: selected),
                    const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelPadding: EdgeInsets.symmetric(horizontal: 11),
                      tabs: [
                        Tab(text: 'BODY'),
                        Tab(text: 'HAIR'),
                        Tab(text: 'FACE'),
                        Tab(text: 'CLOTHES'),
                        Tab(text: 'EXTRAS'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          for (final tab in _tabs)
                            _CreatorTab(
                              tab: tab,
                              state: selected.gachaState,
                              tables: tables,
                              onNumericChanged: onNumericChanged,
                              onColorChanged: onColorChanged,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.character});

  final ProjectCharacter character;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _ink,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            character.name.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _signal, fontWeight: FontWeight.w900),
          ),
          Text(
            'CANONICAL 445-FIELD CHARACTER',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 9,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatorTab extends StatelessWidget {
  const _CreatorTab({
    required this.tab,
    required this.state,
    required this.tables,
    required this.onNumericChanged,
    required this.onColorChanged,
  });

  final _TabSpec tab;
  final GachaCharacterState state;
  final ResolverTables tables;
  final void Function(String field, int value) onNumericChanged;
  final void Function(String field, Color value) onColorChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: [
        for (var index = 0; index < tab.groups.length; index++)
          _ControlGroup(
            group: tab.groups[index],
            state: state,
            tables: tables,
            initiallyExpanded: index == 0,
            onNumericChanged: onNumericChanged,
            onColorChanged: onColorChanged,
          ),
      ],
    );
  }
}

class _ControlGroup extends StatelessWidget {
  const _ControlGroup({
    required this.group,
    required this.state,
    required this.tables,
    required this.initiallyExpanded,
    required this.onNumericChanged,
    required this.onColorChanged,
  });

  final _GroupSpec group;
  final GachaCharacterState state;
  final ResolverTables tables;
  final bool initiallyExpanded;
  final void Function(String field, int value) onNumericChanged;
  final void Function(String field, Color value) onColorChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFB4B1A8)),
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.only(bottom: 5),
        title: Text(
          group.title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        children: [
          for (final field in group.numericFields)
            _NumericControl(
              label: field.label,
              value: state.numeric(field.field),
              min:
                  field.min ??
                  tables.editorValueRangeFor(field.field)?.minValue ??
                  0,
              max:
                  field.max ??
                  tables.editorValueRangeFor(field.field)?.maxValue ??
                  999,
              step: field.step,
              onChanged: (value) => onNumericChanged(field.field, value),
            ),
          for (final field in group.colorFields)
            _ColorControl(
              label: field.label,
              value: state.color(field.field),
              onChanged: (value) => onColorChanged(field.field, value),
            ),
        ],
      ),
    );
  }
}

class _NumericControl extends StatelessWidget {
  const _NumericControl({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
          _StepButton(
            icon: Icons.remove,
            onPressed: () {
              final next = value - step;
              onChanged(next < min ? max : next);
            },
          ),
          InkWell(
            onTap: () => _promptValue(context),
            child: SizedBox(
              width: 45,
              height: 28,
              child: Center(
                child: Text(
                  '$value',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            onPressed: () {
              final next = value + step;
              onChanged(next > max ? min : next);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _promptValue(BuildContext context) async {
    final text = TextEditingController(text: '$value');
    final next = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set $label'),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
          ],
          decoration: InputDecoration(labelText: '$min-$max'),
          onSubmitted: (raw) {
            final parsed = int.tryParse(raw);
            if (parsed != null) {
              Navigator.pop(context, parsed.clamp(min, max));
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(text.text);
              if (parsed != null) {
                Navigator.pop(context, parsed.clamp(min, max));
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    text.dispose();
    if (next != null && next != value) {
      onChanged(next);
    }
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton.filledTonal(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
      ),
    );
  }
}

class _ColorControl extends StatelessWidget {
  const _ColorControl({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  static const palette = [
    Color(0xFFF6D6B8),
    Color(0xFFC98C68),
    Color(0xFF70452D),
    Color(0xFF2B211C),
    Color(0xFFEAC77B),
    Color(0xFFC85145),
    Color(0xFF46699B),
    Color(0xFF6D4A83),
    Color(0xFFE9E5DA),
    Color(0xFF111111),
  ];

  final String label;
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final rgb = value.toARGB32() & 0x00FFFFFF;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
          Text(
            '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}',
            style: const TextStyle(fontSize: 9),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<Color>(
            tooltip: 'Choose color',
            onSelected: onChanged,
            itemBuilder: (context) => [
              for (final color in palette)
                PopupMenuItem(
                  value: color,
                  child: Container(width: 140, height: 22, color: color),
                ),
            ],
            child: Container(
              width: 28,
              height: 28,
              color: value,
              foregroundDecoration: BoxDecoration(
                border: Border.all(color: _ink),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumericField {
  const _NumericField(
    this.field,
    this.label, {
    this.min,
    this.max,
    this.step = 1,
  });

  final String field;
  final String label;
  final int? min;
  final int? max;
  final int step;
}

class _ColorField {
  const _ColorField(this.field, this.label);

  final String field;
  final String label;
}

class _GroupSpec {
  const _GroupSpec(
    this.title, {
    this.numericFields = const [],
    this.colorFields = const [],
  });

  final String title;
  final List<_NumericField> numericFields;
  final List<_ColorField> colorFields;
}

class _TabSpec {
  const _TabSpec(this.groups);

  final List<_GroupSpec> groups;
}

const _tabs = [
  _TabSpec([
    _GroupSpec(
      'BODY AND POSE',
      numericFields: [
        _NumericField('heightx', 'Body width', min: 1, max: 30),
        _NumericField('heighty', 'Body height', min: 1, max: 20),
        _NumericField('pose', 'Pose', min: 1, max: 603),
        _NumericField('headlayer', 'Head layer', min: 1, max: 3),
      ],
    ),
    _GroupSpec(
      'SKIN COLORS',
      colorFields: [
        _ColorField('skincolor1x', 'Skin fill'),
        _ColorField('skincolor2x', 'Skin outline'),
      ],
    ),
  ]),
  _TabSpec([
    _GroupSpec(
      'HAIR PARTS',
      numericFields: [
        _NumericField('fronthair', 'Front hair', min: 0, max: 328),
        _NumericField('rearhair', 'Rear hair', min: 0, max: 228),
        _NumericField('backhair', 'Back hair', min: 0, max: 103),
        _NumericField('ponytail', 'Ponytail', min: 0, max: 85),
        _NumericField('ahoge', 'Ahoge', min: 0, max: 51),
      ],
    ),
    _GroupSpec(
      'PRIMARY COLORS',
      colorFields: [
        _ColorField('fronthaircolor1x', 'Front primary'),
        _ColorField('rearhaircolor1x', 'Rear primary'),
        _ColorField('backhaircolor1x', 'Back primary'),
        _ColorField('ponytailcolor1x', 'Ponytail primary'),
        _ColorField('ahogecolor1x', 'Ahoge primary'),
      ],
    ),
    _GroupSpec(
      'SECONDARY AND OUTLINE',
      colorFields: [
        _ColorField('fronthaircolor2x', 'Front secondary'),
        _ColorField('fronthaircolor3x', 'Front outline'),
        _ColorField('rearhaircolor2x', 'Rear secondary'),
        _ColorField('rearhaircolor3x', 'Rear outline'),
        _ColorField('backhaircolor2x', 'Back secondary'),
        _ColorField('backhaircolor3x', 'Back outline'),
        _ColorField('ponytailcolor2x', 'Ponytail secondary'),
        _ColorField('ponytailcolor3x', 'Ponytail outline'),
        _ColorField('ahogecolor2x', 'Ahoge secondary'),
        _ColorField('ahogecolor3x', 'Ahoge outline'),
      ],
    ),
    _GroupSpec(
      'HAIR TRANSFORMS',
      numericFields: [
        _NumericField(
          'fronthairxpos',
          'Front hair X',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField(
          'fronthairypos',
          'Front hair Y',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField('fronthairxscale', 'Front hair width', min: 1, max: 20),
        _NumericField('fronthairyscale', 'Front hair height', min: 1, max: 20),
        _NumericField('fronthairrot', 'Front hair frame', min: 1, max: 20),
        _NumericField(
          'backhairxpos',
          'Back hair X',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField(
          'backhairypos',
          'Back hair Y',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField('backhairxscale', 'Back hair width', min: 1, max: 20),
        _NumericField('backhairyscale', 'Back hair height', min: 1, max: 20),
        _NumericField('backhairrot', 'Back hair frame', min: 1, max: 13),
        _NumericField(
          'ponytailxpos',
          'Ponytail X',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField(
          'ponytailypos',
          'Ponytail Y',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField('ponytailxscale', 'Ponytail width', min: 1, max: 20),
        _NumericField('ponytailyscale', 'Ponytail height', min: 1, max: 20),
        _NumericField(
          'ponytailrot',
          'Ponytail rotation',
          min: 0,
          max: 357,
          step: 3,
        ),
        _NumericField('ahogexpos', 'Ahoge X', min: -100, max: 100, step: 2),
        _NumericField('ahogeypos', 'Ahoge Y', min: -100, max: 100, step: 2),
        _NumericField('ahogexscale', 'Ahoge width', min: 1, max: 20),
        _NumericField('ahogeyscale', 'Ahoge height', min: 1, max: 20),
        _NumericField('ahogerot', 'Ahoge rotation', min: 0, max: 357, step: 3),
      ],
    ),
  ]),
  _TabSpec([
    _GroupSpec(
      'FACE PRESET AND FEATURES',
      numericFields: [
        _NumericField('facepreset', 'Face preset', min: 1, max: 40),
        _NumericField('eyes1x', 'Left eye', min: 0, max: 131),
        _NumericField('eyes2x', 'Right eye', min: 0, max: 131),
        _NumericField('pupil1x', 'Left pupil', min: 0, max: 100),
        _NumericField('pupil2x', 'Right pupil', min: 0, max: 100),
        _NumericField('eyebrows1x', 'Left eyebrow', min: 0, max: 100),
        _NumericField('eyebrows2x', 'Right eyebrow', min: 0, max: 100),
        _NumericField('mouth', 'Mouth', min: 0, max: 256),
        _NumericField('nose', 'Nose', min: 0, max: 20),
        _NumericField('blush', 'Blush', min: 0, max: 10),
      ],
    ),
    _GroupSpec(
      'EYE AND PUPIL COLORS',
      colorFields: [
        _ColorField('eye1color1x', 'Left eye primary'),
        _ColorField('eye1color2x', 'Left eye secondary'),
        _ColorField('eye2color1x', 'Right eye primary'),
        _ColorField('eye2color2x', 'Right eye secondary'),
        _ColorField('pupil1color1x', 'Left pupil'),
        _ColorField('pupil2color1x', 'Right pupil'),
      ],
    ),
    _GroupSpec(
      'EXPRESSION COLORS',
      colorFields: [
        _ColorField('eyebrows1color1x', 'Left eyebrow'),
        _ColorField('eyebrows2color1x', 'Right eyebrow'),
        _ColorField('mouthcolor1x', 'Mouth primary'),
        _ColorField('mouthcolor2x', 'Mouth secondary'),
        _ColorField('nosecolor1x', 'Nose'),
        _ColorField('blushcolorx', 'Blush'),
      ],
    ),
    _GroupSpec(
      'FACE TRANSFORMS',
      numericFields: [
        _NumericField('leyexpos', 'Left eye X', min: -100, max: 100),
        _NumericField('leyeypos', 'Left eye Y', min: -100, max: 100),
        _NumericField('leyesize', 'Left eye width', min: 1, max: 20),
        _NumericField('leyesizey', 'Left eye height', min: 1, max: 20),
        _NumericField(
          'leyerot',
          'Left eye rotation',
          min: -177,
          max: 180,
          step: 3,
        ),
        _NumericField('reyexpos', 'Right eye X', min: -100, max: 100),
        _NumericField('reyeypos', 'Right eye Y', min: -100, max: 100),
        _NumericField('reyesize', 'Right eye width', min: 1, max: 20),
        _NumericField('reyesizey', 'Right eye height', min: 1, max: 20),
        _NumericField(
          'reyerot',
          'Right eye rotation',
          min: -177,
          max: 180,
          step: 3,
        ),
        _NumericField('lpupilxpos', 'Left pupil X', min: -50, max: 50),
        _NumericField('lpupilypos', 'Left pupil Y', min: -50, max: 50),
        _NumericField('rpupilxpos', 'Right pupil X', min: -50, max: 50),
        _NumericField('rpupilypos', 'Right pupil Y', min: -50, max: 50),
        _NumericField('mouthxpos', 'Mouth X', min: -100, max: 100),
        _NumericField('mouthypos', 'Mouth Y', min: -100, max: 100),
        _NumericField('mouthsize', 'Mouth width', min: 1, max: 20),
        _NumericField('mouthsizey', 'Mouth height', min: 1, max: 20),
        _NumericField('mouthrot', 'Mouth rotation', min: 0, max: 357, step: 3),
        _NumericField('nosexpos', 'Nose X', min: -10, max: 10),
        _NumericField('noseypos', 'Nose Y', min: -10, max: 10),
        _NumericField('nosesize', 'Nose width', min: 1, max: 20),
        _NumericField('nosesizey', 'Nose height', min: 1, max: 20),
        _NumericField('noserot', 'Nose rotation', min: 0, max: 357, step: 3),
      ],
    ),
  ]),
  _TabSpec([
    _GroupSpec(
      'UPPER CLOTHING',
      numericFields: [
        _NumericField('shirt', 'Shirt', min: 1, max: 114),
        _NumericField('shirtex', 'Jacket', min: 0, max: 59),
        _NumericField('sleeves1x', 'Front sleeve', min: 0, max: 94),
        _NumericField('sleeves2x', 'Back sleeve', min: 0, max: 94),
      ],
    ),
    _GroupSpec(
      'LOWER CLOTHING',
      numericFields: [
        _NumericField('pants1x', 'Front pants', min: 1, max: 41),
        _NumericField('pants2x', 'Back pants', min: 1, max: 41),
        _NumericField('socks1x', 'Front socks', min: 0, max: 127),
        _NumericField('socks2x', 'Back socks', min: 0, max: 127),
        _NumericField('shoes1x', 'Front shoes', min: 0, max: 95),
        _NumericField('shoes2x', 'Back shoes', min: 0, max: 95),
        _NumericField('belt1x', 'Front belt', min: 0, max: 119),
        _NumericField('belt2x', 'Back belt', min: 0, max: 119),
      ],
    ),
    _GroupSpec(
      'UPPER COLORS',
      colorFields: [
        _ColorField('shirtcolor1x', 'Shirt primary'),
        _ColorField('shirtcolor2x', 'Shirt secondary'),
        _ColorField('shirtcolor3x', 'Shirt outline'),
        _ColorField('shirtexcolor1x', 'Jacket primary'),
        _ColorField('sleeves1color1x', 'Front sleeve'),
        _ColorField('sleeves2color1x', 'Back sleeve'),
      ],
    ),
    _GroupSpec(
      'LOWER COLORS',
      colorFields: [
        _ColorField('pants1color1x', 'Front pants'),
        _ColorField('pants2color1x', 'Back pants'),
        _ColorField('socks1color1x', 'Front socks'),
        _ColorField('socks2color1x', 'Back socks'),
        _ColorField('shoes1color1x', 'Front shoes'),
        _ColorField('shoes2color1x', 'Back shoes'),
        _ColorField('belt1color1x', 'Front belt'),
        _ColorField('belt2color1x', 'Back belt'),
      ],
    ),
  ]),
  _TabSpec([
    _GroupSpec(
      'HEAD ACCESSORIES',
      numericFields: [
        _NumericField('hat', 'Hat', min: 0, max: 126),
        _NumericField('glasses', 'Glasses', min: 0, max: 53),
        _NumericField('accessory1x', 'Face accessory 1', min: 0, max: 132),
        _NumericField('accessory2x', 'Face accessory 2', min: 0, max: 132),
        _NumericField('accessory3x', 'Face accessory 3', min: 0, max: 132),
        _NumericField('other1x', 'Other accessory 1', min: 0, max: 230),
        _NumericField('other2x', 'Other accessory 2', min: 0, max: 230),
        _NumericField('other3x', 'Other accessory 3', min: 0, max: 230),
        _NumericField('other4x', 'Other accessory 4', min: 0, max: 230),
      ],
    ),
    _GroupSpec(
      'OUTERWEAR AND CREATURE PARTS',
      numericFields: [
        _NumericField('scarf1x', 'Front scarf', min: 0, max: 127),
        _NumericField('scarf2x', 'Back scarf', min: 0, max: 127),
        _NumericField('cape', 'Cape', min: 0, max: 63),
        _NumericField('tail', 'Tail', min: 0, max: 100),
        _NumericField('wings1x', 'Left wing', min: 0, max: 61),
        _NumericField('wings2x', 'Right wing', min: 0, max: 61),
      ],
    ),
    _GroupSpec(
      'PROPS AND WEAPONS',
      numericFields: [
        _NumericField('weapon1x', 'Front weapon', min: 0, max: 291),
        _NumericField('weapon2x', 'Back weapon', min: 0, max: 291),
        _NumericField('shield', 'Shield', min: 0, max: 41),
        _NumericField('propsize1x', 'Front prop scale', min: 1, max: 20),
        _NumericField(
          'proprot1x',
          'Front prop rotation',
          min: 0,
          max: 357,
          step: 3,
        ),
        _NumericField(
          'propxpos1x',
          'Front prop X',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField(
          'propypos1x',
          'Front prop Y',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField('propsize2x', 'Back prop scale', min: 1, max: 20),
        _NumericField(
          'proprot2x',
          'Back prop rotation',
          min: 0,
          max: 357,
          step: 3,
        ),
        _NumericField(
          'propxpos2x',
          'Back prop X',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField(
          'propypos2x',
          'Back prop Y',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField('shieldsize', 'Shield scale', min: 1, max: 20),
        _NumericField(
          'shieldrot',
          'Shield rotation',
          min: 0,
          max: 357,
          step: 3,
        ),
        _NumericField('shieldxpos', 'Shield X', min: -100, max: 100, step: 2),
        _NumericField('shieldypos', 'Shield Y', min: -100, max: 100, step: 2),
      ],
    ),
    _GroupSpec(
      'HEAD ACCESSORY TRANSFORMS',
      numericFields: [
        _NumericField('hatxpos', 'Hat X', min: -100, max: 100, step: 2),
        _NumericField('hatypos', 'Hat Y', min: -100, max: 100, step: 2),
        _NumericField('hatsize', 'Hat width', min: 1, max: 20),
        _NumericField('hatsizey', 'Hat height', min: 1, max: 20),
        _NumericField('hatrot', 'Hat rotation', min: 0, max: 357, step: 3),
        _NumericField('glassesxpos', 'Glasses X', min: -100, max: 100, step: 2),
        _NumericField('glassesypos', 'Glasses Y', min: -100, max: 100, step: 2),
        _NumericField('glassessize', 'Glasses width', min: 1, max: 20),
        _NumericField('glassessizey', 'Glasses height', min: 1, max: 20),
        _NumericField(
          'glassesrot',
          'Glasses rotation',
          min: 0,
          max: 357,
          step: 3,
        ),
        _NumericField(
          'acc1xpos',
          'Accessory 1 X',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField(
          'acc1ypos',
          'Accessory 1 Y',
          min: -100,
          max: 100,
          step: 2,
        ),
        _NumericField('acc1size', 'Accessory 1 width', min: 1, max: 20),
        _NumericField('acc1sizey', 'Accessory 1 height', min: 1, max: 20),
        _NumericField(
          'acc1rot',
          'Accessory 1 rotation',
          min: 0,
          max: 357,
          step: 3,
        ),
      ],
    ),
    _GroupSpec(
      'CAPE TAIL AND WING TRANSFORMS',
      numericFields: [
        _NumericField('capexpos', 'Cape X', min: -100, max: 100, step: 2),
        _NumericField('capeypos', 'Cape Y', min: -100, max: 100, step: 2),
        _NumericField('capesize', 'Cape width', min: 1, max: 20),
        _NumericField('capesizey', 'Cape height', min: 1, max: 20),
        _NumericField('caperot', 'Cape rotation', min: 0, max: 357, step: 3),
        _NumericField('tailxpos', 'Tail X', min: -100, max: 100, step: 2),
        _NumericField('tailypos', 'Tail Y', min: -100, max: 100, step: 2),
        _NumericField('tailsize', 'Tail width', min: 1, max: 20),
        _NumericField('tailsizey', 'Tail height', min: 1, max: 20),
        _NumericField('tailrot', 'Tail rotation', min: 0, max: 357, step: 3),
        _NumericField('wingxpos', 'Wing X', min: -100, max: 100, step: 2),
        _NumericField('wingypos', 'Wing Y', min: -100, max: 100, step: 2),
        _NumericField('wingsize', 'Wing width', min: 1, max: 20),
        _NumericField('wingsizey', 'Wing height', min: 1, max: 20),
        _NumericField('wingrot', 'Wing rotation', min: 0, max: 357, step: 3),
      ],
    ),
    _GroupSpec(
      'ACCESSORY COLORS',
      colorFields: [
        _ColorField('hatcolor1x', 'Hat primary'),
        _ColorField('glassescolor1x', 'Glasses primary'),
        _ColorField('accessory1color1x', 'Accessory 1 primary'),
        _ColorField('accessory2color1x', 'Accessory 2 primary'),
        _ColorField('accessory3color1x', 'Accessory 3 primary'),
        _ColorField('other1color1x', 'Other 1 primary'),
        _ColorField('other2color1x', 'Other 2 primary'),
        _ColorField('other3color1x', 'Other 3 primary'),
        _ColorField('other4color1x', 'Other 4 primary'),
      ],
    ),
    _GroupSpec(
      'PROP AND CREATURE COLORS',
      colorFields: [
        _ColorField('scarf1color1x', 'Front scarf'),
        _ColorField('scarf2color1x', 'Back scarf'),
        _ColorField('capecolor1x', 'Cape'),
        _ColorField('tailcolor1x', 'Tail'),
        _ColorField('wings1color1x', 'Left wing'),
        _ColorField('wings2color1x', 'Right wing'),
        _ColorField('weapon1color1x', 'Front weapon'),
        _ColorField('weapon2color1x', 'Back weapon'),
        _ColorField('shieldcolor1x', 'Shield'),
      ],
    ),
  ]),
];
