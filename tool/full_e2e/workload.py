"""Scale a historical fixture and its clients without changing server capacity."""
from copy import deepcopy


def staff_counts(manifest):
    scale = manifest.get('staff_scale', manifest.get('scale', 1))
    return dict(judges=110*scale, admins=10*scale, superintendents=15*scale,
                checkin=30*scale, support=25*scale, total=135*scale)


def scale_manifest(original, scale=1, staff_scale=None):
    if not isinstance(scale, int) or scale < 1:
        raise ValueError('Scale must be a positive integer')
    staff_scale = scale if staff_scale is None else staff_scale
    if not isinstance(staff_scale, int) or staff_scale < 1:
        raise ValueError('Staff scale must be a positive integer')
    m = deepcopy(original)
    m.update(scale=scale, staff_scale=staff_scale,
             historical_totals=deepcopy(original['totals']))
    m['totals'] = {k:v*scale for k,v in original['totals'].items()}
    for s in m['sections']:
        for key in ('entries','exhibitors'):
            s[key] *= scale
        for key in ('first_entry','first_exhibitor'):
            s[key] = (s[key]-1)*scale+1
        s['last_entry'] *= scale
    for group in ('classes','breeds'):
        for row in m[group]:
            row['count'] *= scale
            row['first'] = (row['first']-1)*scale+1
            row['last'] *= scale
            s = m['sections'][row['section']-1]
            first = (row['first']-s['first_entry'])*s['exhibitors']//s['entries']
            last = (row['last']-s['first_entry'])*s['exhibitors']//s['entries']
            row['exhibitors'] = last-first+1
    m['assumptions'] = [
        f'Historical breed and class counts multiplied exactly by {scale}.',
        'One Open A and one Youth A, separate coops, no exhibitor overlap.',
        'Synthetic ownership, individual animal records, placements and winners.',
        'Open class proportions derive from the historical Youth classes.',
        'One animal record per entry, including each meat pen; not a physical rabbit census.',
        f'Client concurrency multiplied by {staff_scale}; server resources unchanged.',
    ]
    return m
