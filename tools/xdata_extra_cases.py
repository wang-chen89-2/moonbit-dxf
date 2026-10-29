"""Additional hand-built namespace boundaries, frozen before product edits."""
from xdata_cases import source_tags, text, wire, typed


def extra_cases():
    tags=source_tags('AC1015'); marks={item[3]:i for i,item in enumerate(tags) if item[3]}
    empty=tags[:marks['b_marker']+1]+tags[marks['next_record']:]
    private=tags[:marks['b_close']+1]+[text(102,'{UNCLOSED')]+tags[marks['b_close']+1:]
    deep=tags[:marks['b_open']+1]+[text(1002,'{')]+tags[marks['b_open']+1:marks['b_close']]+[text(1002,'}')]+tags[marks['b_close']:]
    result=[]
    for name,values,error in [('empty-application',empty,None),('unclosed-private-scope',private,'XDATA application contains an unclosed private group'),('deep-list',deep,None)]:
        indices={item[3]:i for i,item in enumerate(values) if item[3]}
        data=values[indices['b_marker']+1:indices['next_record']]
        result.append({'name':name,'source':b''.join(wire(item) for item in values),'error':error,
                       'expectedData':None if error else [{'code':item[0],'value':typed(item)} for item in data],
                       'expectedSelectedIndex':indices.get('b_text')})
    assert result[0]['expectedData']==[]
    assert result[2]['expectedSelectedIndex']==53 and len(result[2]['expectedData'])==9
    return result
