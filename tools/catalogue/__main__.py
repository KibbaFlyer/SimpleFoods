import argparse
import json
from .build import build
from .core import ValidationError

def main():
    parser=argparse.ArgumentParser(description='Build explicit allowlisted public catalogue inputs offline')
    parser.add_argument('--input',required=True)
    parser.add_argument('--registry',required=True)
    parser.add_argument('--output',required=True)
    parser.add_argument('--allow-input',action='append',default=[],help='Exact trusted public fixture/input file; repeat')
    parser.add_argument('--allow-evidence',action='append',default=[])
    parser.add_argument('--previous')
    parser.add_argument('--mode',choices=['development','production'],default='development')
    args=parser.parse_args()
    try:
        manifest=build(args.input,args.registry,args.output,args.allow_input,args.mode,args.previous,args.allow_evidence)
    except (ValidationError,OSError,ValueError,TypeError,KeyError) as error:
        parser.exit(2,'Catalogue build rejected: '+str(error)+'\n')
    print(json.dumps(manifest,sort_keys=True))

if __name__=='__main__': main()
