class Controller < Sinatra::Base

  get %r{/api/count(:?\.(?<format>json))?} do
    format = params['format'] || 'json'

    if params[:base].empty? and !params[:targets].empty?
      api_response format, 400, {
        error: "invalid_input",
        error_description: "Parameter \"base\" is required, example: http://example.com"
      }
    end

    if params[:base]
      base = URI.parse params[:base]
      if base.nil?
        api_response format, 400, {
          error: "invalid_input",
          error_description: "Invalid parameter \"base\""
        }
      end

      site = Site.first :domain => base.host
      if site.nil?
        api_response format, 404, {
          error: "not_found",
          error_description: "The site was not found"
        }
      end

      if site.public_access == false
        api_response format, 401, {
          error: "forbidden",
          error_description: "This site does not allow public access to its mentions"
        }
      end

      if params[:targets].empty?
        api_response format, 400, {
          error: "invalid_input",
          error_description: "Parameter \"target\" is required"
        }
      end

      targets = Page.all :href => params[:targets].split(",").map{|t| "#{params[:base]}#{t}"}
      if targets.nil?
        api_response format, 404, {
          error: "not_found",
          error_description: "The specified link was not found"
        }
      end

      counts = {}
      targets.each do |t|
        links = t.links.count(:verified => true)
        counts[t.href] = links
      end

      if format == 'json'
        api_response format, 200, {
          count: counts
        }
      else
        atom_feed = {links: link_array}
        api_response format, 200, atom_feed
      end

    else

      if params[:target].empty? and params[:access_token].empty?
        api_response format, 400, {
          error: "invalid_input",
          error_description: "Either an access token or a target URI is required"
        }
      end

      if params[:access_token].empty?
        target = Page.first :href => params[:target]
        if target.nil?
          links = 0
        else
          if target.site.public_access == false
            api_response format, 401, {
              error: "forbidden",
              error_description: "This site does not allow public access to its mentions"
            }
          end

          links = target.links.count(:verified => true)
        end
      else

        account = Account.first :token => params[:access_token]

        if account.nil?
          api_response format, 401, {
            error: "forbidden",
            error_description: "Access token was not valid"
          }
        end

        target = account.sites.pages.first :href => params[:target]

        if target.nil?
          links = 0
        else
          links = target.links.count(:verified => true)
        end
      end

      if format == 'json'
        api_response format, 200, {
          count: links
        }
      else
        atom_feed = {count: count}
        api_response format, 200, atom_feed
      end

    end
  end

  get %r{/api/(links|mentions)(:?\.(?<format>json|atom|jf2))?} do
    format = params['format'] || 'json'

    if params[:token]
      params[:access_token] = params[:token]
    end

    if params[:perPage]
      limit = params[:perPage].to_i
    else
      limit = 20
    end

    if params[:page]
      pageNum = params[:page].to_i
    else
      pageNum = 0
    end

    if params[:target].empty? and params[:access_token].empty?
      api_response format, 400, {
        error: "invalid_input",
        error_description: "Either a token or a target URL is required"
      }
    end

    if params[:target].empty?
      # access token required for everything except target requests

      account = Account.first :token => params[:access_token]

      if account.nil?
        api_response format, 401, {
          error: "forbidden",
          error_description: "Access token was not valid"
        }
      end

      if params[:domain]
        links = account.sites.all(:domain => params[:domain]).pages.links.all(:verified => true, :order => [:created_at.desc], :offset => (pageNum * limit), :limit => limit)
      else
        links = account.sites.pages.links.all(:verified => true, :order => [:created_at.desc], :offset => (pageNum * limit), :limit => limit)
      end

    else

      targets = Page.all :href => params[:target]

      if targets.nil?
        api_response format, 200, {
          links: []
        }
      end

      links = targets.links.all(:verified => true, :order => [:created_at.desc], :offset => (pageNum * limit), :limit => limit)

    end

    if format == 'json'
      api_response format, 200, Formats.links_to_json(links)
    elsif format =='jf2'
      api_response 'json', 200, Formats.links_to_jf2(links)
    else
      base_url = "https://webmention.io"
      atom_url = "#{base_url}/api/mentions.atom"
      feed = Atom::Feed.new{|f|
        f.title = "Mentions"
        f.links << Atom::Link.new(:href => atom_url)
        f.updated = link_array.collect{|l| l[:verified_date]}.max
        f.authors << Atom::Person.new(:name => "webmention.io")
        f.id = atom_url
        link_array.each do |link|
          source = URI.parse link[:source]
          target = URI.parse link[:target]
          target.path = "/" if target.path == ""
          f.entries << Atom::Entry.new do |entry|
            entry.title = "#{source.host} linked to #{target.path}"
            entry.id = "#{base_url}/api/mention/#{link[:id]}"
            entry.updated = link[:verified_date]
            entry.summary = "#{link[:source]} linked to #{link[:target]}"
            entry.content = Atom::Content::Xhtml.new("<p><a href=\"#{link[:source]}\">#{link[:source]}</a> linked to <a href=\"#{link[:target]}\">#{link[:target]}</a></p>")
          end
        end
      }

      api_response format, 200, feed.to_xml
    end
  end

end
