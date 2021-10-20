from collections import OrderedDict
import json
import re
import os
import glob
from typing import TYPE_CHECKING
import warnings

# References:
# https://github.com/jgm/pandoc/blob/master/src/Text/Pandoc/Citeproc/BibTeX.hs
# https://github.com/andras-simonyi/citeproc-el/wiki/BibLaTeX-CSL-mapping
# https://github.com/brechtm/citeproc-py/blob/master/citeproc/source/bibtex/bibtex.py
# https://github.com/citation-js/bibtex-mappings/blob/main/biblatex/output/types.json


class BibData(OrderedDict):
    def __init__(self, path):
        super().__init__({
            'description': 'Bib CSL mapping',
            'types': dict(),
            'fields': dict(),
            'macros': dict(),
        })

        if os.path.exists(path):
            with open(path) as f:
                self.update(json.load(f))
        else:
            warnings.warn(f'Invalid path "{path}".')

        self.texmf_dist = None
        if not self.texmf_dist:
            paths = glob.glob('/usr/local/texlive/*/texmf-dist')
            if paths:
                self.texmf_dist = sorted(paths)[-1]

    def update_bibtex(self):
        if not self.texmf_dist:
            return
        bst_path = os.path.join(self.texmf_dist, 'bibtex', 'bst', 'base',
                                'plain.bst')
        self.update_bst(bst_path, 'bibtex')

    def update_bst(self, path, source):
        if not os.path.exists(path):
            warnings.warn(f'Invalid path "{path}".')
            return

        with open(path) as f:
            contents = f.read()

        if source == "bibtex":
            for match in re.finditer(r'FUNCTION\s*\{\s*(\w+)\s*\}', contents):
                entry_type = match.group(1)
                if entry_type in [
                        'output', 'not', 'and', 'or', 'emphasize', 'sortify',
                        'presort'
                ]:
                    continue
                if entry_type not in self['types']:
                    self['types'][entry_type] = {
                        'csl': None,
                        'source': source,
                    }

        fields_str = re.search(r'ENTRY\s*\{\s*([^}]+)\s*\}', contents)
        if fields_str:
            for field in fields_str.group(1).split():
                field = field.strip()
                if field not in self['fields']:
                    self['fields'][field] = {
                        'csl': None,
                        'source': source,
                    }

        for match in re.finditer(
                r'MACRO\s*\{\s*(\S+)\s*\}\s*\{\s*"([^"]*)"\s*\}', contents):
            macro = match.group(1)
            value = match.group(2)
            if macro not in self['macros']:
                self['macros'][macro] = {
                    'value': value,
                    'source': source,
                }

    def update_biblatex(self):
        if not self.texmf_dist:
            return
        source = "biblatex"
        biblatex_path = os.path.join(self.texmf_dist, 'tex', 'latex',
                                     'biblatex')
        with open(os.path.join(biblatex_path, 'blx-dm.def')) as f:
            contents = f.read()

        for match in re.finditer(
                r'\\DeclareDatamodelEntrytypes(\[.*\])?\{(([^}]|\s)*)\}',
                contents):
            for entry_type in match.group(2).split(','):
                entry_type = entry_type.strip()
                if entry_type not in self['types']:
                    self['types'][entry_type] = {
                        'csl': None,
                        'source': source,
                    }

        for match in re.finditer(
                r'\\DeclareDatamodelFields(\[(.*)\])?\{(([^}]|\s)*)\}',
                contents):
            field_type = re.search(r'datatype=(\w+)', match.group(2)).group(1)
            for field in match.group(3).split(','):
                field = field.strip()
                if field not in self['fields']:
                    self['fields'][field] = {
                        'csl': None,
                        'source': source,
                    }
                if 'type' not in self['fields'][field]:
                    self['fields'][field]['type'] = field_type

        with open(os.path.join(biblatex_path, 'biblatex.def')) as f:
            contents = f.read()

        for match in re.finditer(r'typesource=(\w+),\s*typetarget=(\w+)',
                                 contents):
            entry_type = match.group(1)
            target = match.group(2)
            if entry_type not in self['types']:
                self['types'][entry_type] = {
                    'csl': None,
                    'source': source,
                }
            if 'alias' not in self['types'][entry_type]:
                self['types'][entry_type]['alias'] = target

        for match in re.finditer(r'fieldsource=(\w+),\s*fieldtarget=(\w+)',
                                 contents):
            field = match.group(1)
            target = match.group(2)
            if field not in self['fields']:
                self['fields'][field] = {
                    'csl': None,
                    'source': source,
                }
            if 'alias' not in self['fields'][field]:
                self['fields'][field]['alias'] = target

    def update_alias_mappings(self):
        for category in ['types', 'fields']:
            for field, value in self[category].items():
                if 'alias' not in value:
                    continue
                alias = self[category][value['alias']]
                if 'csl' in alias:
                    value['csl'] = alias['csl']
                if 'type' in alias:
                    value['type'] = alias['type']

    def check_csl_schema(self):
        csl_data_path = '../schema/schemas/input/csl-data.json'
        if not os.path.exists(csl_data_path):
            warnings.warn(f'Invalid path "{csl_data_path}".')
            return
        with open(csl_data_path) as f:
            csl_data = json.load(f)

        # with open('csl-data-v1.1.json') as f:
        #     csl_1_1_data = json.load(f)
        # csl_1_1_fields = csl_1_1_data['definitions']['refitem']['properties'].keys()

        for category in ['types', 'fields']:
            if category == "types":
                csl_fields = csl_data['items']['properties']['type']['enum']
            elif category == "fields":
                csl_fields = csl_data['items']['properties'].keys()

            for field, value in self[category].items():
                if 'csl' not in value:
                    print(f'Empty CSL mapping in "{field}".')
                    continue
                target = value['csl']

                if target and target not in csl_fields:
                    print(f'Invalid CSL type "{target}".')
                if category == 'fields' and 'type' not in value:
                    print(f'Empty type in field "{field}".')


    def sort_keys(self):
        self['types'] = OrderedDict(sorted(self['types'].items()))
        self['fields'] = OrderedDict(sorted(self['fields'].items()))

        for entry_type, value in self['types'].items():
            self['types'][entry_type] = OrderedDict(sorted(value.items()))
        for field, value in self['fields'].items():
            self['fields'][field] = OrderedDict(sorted(value.items()))

    def export_markdown(self):
        res = '# Bib CSL mapping\n'
        for category in ['types', 'fields']:
            if category == 'types':
                res += '\n\n## Item Types\n'
            elif category == 'fields':
                res += '\n\n## Fields\n'
            res += '\nBib|CSL|Notes\n-|-|-\n'

            for field, contents in self[category].items():
                if re.match(
                        r'(custom[a-f]|editor[a-c]|editor[a-c]type|name[a-c]|name[a-c]type|list[a-f]|user[a-f]|verb[a-c])',
                        field):
                    continue

                field = f"`@{field}`"
                target = contents['csl']
                if not target:
                    target = '-'
                else:
                    target = f"`{target}`"
                if 'notes' in contents:
                    notes = contents['notes']
                else:
                    notes = ''
                if 'alias' in contents:
                    alias = contents['alias']
                    if category == "types":
                        alias = '@' + alias
                    notes = f'Alias for `{alias}`. ' + notes
                notes = notes.strip()
                line = f'{field}|{target}|{notes}\n'
                res += line

        with open('doc/bib-csl-mapping.md', 'w') as f:
            f.write(res)


if __name__ == '__main__':
    bib_data_path = 'citeproc/citeproc-bib-data.json'
    bib_data = BibData(bib_data_path)

    bib_data.update_bibtex()
    bib_data.update_biblatex()
    bib_data.update_alias_mappings()

    bib_data.check_csl_schema()
    bib_data.sort_keys()
    bib_data.export_markdown()

    with open(bib_data_path, 'w') as f:
        json.dump(bib_data, f, indent=4)
        f.write('\n')
